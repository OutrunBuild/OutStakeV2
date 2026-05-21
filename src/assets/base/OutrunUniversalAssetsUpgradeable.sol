// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

// uAsset (universal asset) — a receipt token minted by staking positions.
// Each minter (a StakeManager contract) has its own debt tracking:
// mintingCap is the ceiling, amountInMinted is outstanding debt.
// Minters repay by burning uAsset, which reduces their outstanding debt.
// amountInMinted is a minter debt ledger, not a same-chain totalSupply invariant:
// OFT cross-chain sends burn on the source chain and mint on the destination chain
// without changing this minter debt ledger.

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {IUniversalAssets} from "../interfaces/IUniversalAssets.sol";
import {OutrunOFTUpgradeable} from "../omnichain/OutrunOFTUpgradeable.sol";

contract OutrunUniversalAssetsUpgradeable is Initializable, IUniversalAssets, OutrunOFTUpgradeable, UUPSUpgradeable {
    /// @custom:storage-location erc7201:outrun.storage.OutrunUniversalAssets
    struct OutrunUniversalAssetsStorage {
        mapping(address minter => MintingStatus) mintingStatusTable;
    }

    // keccak256(abi.encode(uint256(keccak256("outrun.storage.OutrunUniversalAssets")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant OUTRUN_UNIVERSAL_ASSETS_STORAGE_LOCATION =
        0x2b82e9d5002467e1c5131297c0670c5f52b39ef4cd7112616d88ce4844484100;

    error InvalidOFTUpgradeConfig();
    error DecimalsMismatch(uint8 expected, uint8 provided);

    constructor(uint8 localDecimals_, address lzEndpoint) OutrunOFTUpgradeable(localDecimals_, lzEndpoint) {}

    /// @notice Initializes the uAsset token with name, symbol, decimals, and owner.
    /// @param name_ Token name
    /// @param symbol_ Token symbol
    /// @param decimals_ Token decimals (must match the OFT local decimals)
    /// @param owner_ Initial owner address
    function initialize(string calldata name_, string calldata symbol_, uint8 decimals_, address owner_)
        external
        initializer
    {
        if (decimals_ != _localDecimalsForValidation()) {
            revert DecimalsMismatch(_localDecimalsForValidation(), decimals_);
        }
        __UUPSUpgradeable_init();
        __OutrunOFT_init(name_, symbol_, decimals_, owner_);
    }

    function _getOutrunUniversalAssetsStorage() private pure returns (OutrunUniversalAssetsStorage storage $) {
        // slither-disable-next-line assembly
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := OUTRUN_UNIVERSAL_ASSETS_STORAGE_LOCATION
        }
    }

    function _mintingStatus(address minter) private view returns (MintingStatus storage) {
        return _getOutrunUniversalAssetsStorage().mintingStatusTable[minter];
    }

    /// @notice Returns the full minting status for a minter, including cap and outstanding debt.
    /// @param minter Address of the minter (a StakeManager contract)
    /// @return MintingStatus struct containing mintingCap and amountInMinted
    function mintingStatusTable(address minter) public view returns (MintingStatus memory) {
        return _mintingStatus(minter);
    }

    /// @notice Returns how many more uAsset the minter can mint before hitting its cap.
    /// @param minter Address of the minter
    /// @return amountInMintable Remaining mintable amount (mintingCap - amountInMinted)
    function checkMintableAmount(address minter) external view override returns (uint256 amountInMintable) {
        MintingStatus storage status = _mintingStatus(minter);
        uint256 mintingCap = status.mintingCap;
        uint256 amountInMinted = status.amountInMinted;
        amountInMintable = mintingCap > amountInMinted ? mintingCap - amountInMinted : 0;
    }

    /// @notice Sets the minting cap for a minter. Owner-only.
    /// @param minter Address of the minter
    /// @param mintingCap New maximum number of uAsset this minter can mint
    function setMintingCap(address minter, uint256 mintingCap) public override onlyOwner {
        require(minter != address(0), ZeroInput());

        MintingStatus storage status = _mintingStatus(minter);
        uint256 oldMintingCap = status.mintingCap;
        status.mintingCap = mintingCap;

        emit SetMintingCap(minter, oldMintingCap, mintingCap);
    }

    /// @notice Revokes minting rights for a minter by setting its cap to zero. Owner-only.
    /// @param minter Address of the minter to revoke
    function revokeMinter(address minter) external override onlyOwner {
        require(minter != address(0), ZeroInput());

        MintingStatus storage status = _mintingStatus(minter);
        uint256 oldMintingCap = status.mintingCap;
        status.mintingCap = 0;

        emit RevokeMinter(minter, oldMintingCap);
    }

    /// @notice Moves outstanding debt between minter records without minting or burning tokens.
    /// @dev Owner-only accounting operation. Used when migrating or rebalancing stake manager allocations.
    /// @param from Source minter address
    /// @param to Destination minter address
    /// @param amount Amount of debt to transfer
    function transferMinterDebt(address from, address to, uint256 amount) external override onlyOwner {
        require(from != address(0) && to != address(0) && from != to && amount != 0, ZeroInput());

        MintingStatus storage fromStatus = _mintingStatus(from);
        uint256 fromAmountInMinted = fromStatus.amountInMinted;
        require(fromAmountInMinted >= amount, ReachBurnCap());

        MintingStatus storage toStatus = _mintingStatus(to);
        uint256 toAmountInMinted = toStatus.amountInMinted;
        uint256 toMintingCap = toStatus.mintingCap;
        require(toMintingCap >= toAmountInMinted && amount <= toMintingCap - toAmountInMinted, ReachMintCap());

        fromStatus.amountInMinted = fromAmountInMinted - amount;
        toStatus.amountInMinted = toAmountInMinted + amount;

        emit TransferMinterDebt(from, to, amount);
    }

    /// @notice Mints uAsset tokens to a receiver, increasing the minter's outstanding debt.
    /// @dev Respects the pause state and the minter's minting cap.
    /// @param receiver Address to receive the newly minted tokens
    /// @param amount Amount of uAsset to mint
    function mint(address receiver, uint256 amount) external override whenNotPaused {
        require(amount != 0 && receiver != address(0), ZeroInput());

        MintingStatus storage status = _mintingStatus(msg.sender);
        // Check the minter (msg.sender) hasn't exceeded its cap.
        require(status.amountInMinted + amount <= status.mintingCap, ReachMintCap());

        // Increase minter's outstanding debt.
        status.amountInMinted += amount;
        // Mint uAsset tokens to receiver.
        _mint(receiver, amount);

        emit MintUAsset(msg.sender, receiver, amount);
    }

    /// @notice Burns uAsset from an account and decreases the minter's outstanding debt.
    /// @param account Address whose uAsset will be burned
    /// @param amount Amount of uAsset to burn
    function repay(address account, uint256 amount) external override {
        require(account != address(0) && amount != 0, ZeroInput());

        MintingStatus storage status = _mintingStatus(msg.sender);
        uint256 amountInMinted = status.amountInMinted;
        // Check the minter has enough outstanding debt to cover the repayment.
        require(amountInMinted >= amount, ReachBurnCap());

        // Decrease minter's outstanding debt.
        status.amountInMinted = amountInMinted - amount;

        // If repaying another account's balance, check allowance.
        if (account != msg.sender) _spendAllowance(account, msg.sender, amount);
        // Burn uAsset from the account.
        _burn(account, amount);

        emit BurnUAsset(msg.sender, amount);
    }

    /// @notice Validates that a new implementation preserves the LayerZero OFT configuration.
    /// @dev Ensures endpoint, decimal conversion rate, and local decimals match the current values.
    /// @param newImplementation Address of the new implementation contract
    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner {
        OutrunUniversalAssetsUpgradeable implementation = OutrunUniversalAssetsUpgradeable(newImplementation);
        if (
            address(implementation.endpoint()) != address(endpoint)
                || implementation.decimalConversionRate() != decimalConversionRate
                || implementation.localDecimals() != _localDecimalsForValidation()
        ) revert InvalidOFTUpgradeConfig();
    }
}
