// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

// L2 SY adapter where the yield-bearing token itself is the SY. Deposit and redeem are 1:1
// with the underlying token. The exchange rate comes from a configured oracle (since the
// staking yield accrues on L1/Ethereum mainnet and the L2 token balance doesn't reflect it).

import {SYBaseUpgradeable} from "./SYBaseUpgradeable.sol";
import {ArrayLib} from "../libraries/ArrayLib.sol";
import {IExchangeRateOracle} from "../libraries/oracle/interfaces/IExchangeRateOracle.sol";

contract OutrunL2StakedTokenSYUpgradeable is SYBaseUpgradeable {
    /// @custom:storage-location erc7201:outrun.storage.OutrunL2StakedTokenSY
    // forge-lint: disable-next-line(pascal-case-struct)
    struct OutrunL2StakedTokenSYStorage {
        address exchangeRateOracle;
        // The canonical asset lives on Ethereum mainnet; these fields describe it for
        // position accounting and display purposes.
        address underlyingAssetOnEthAddr;
        uint8 underlyingAssetOnEthDecimals;
    }

    // keccak256(abi.encode(uint256(keccak256("outrun.storage.OutrunL2StakedTokenSY")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant OUTRUN_L2_STAKED_TOKEN_SY_STORAGE_LOCATION =
        0xc47406d15de2f1a441454f67ed7478fdea0ecc904b6c2e82cf019a344492a300;

    event SetExchangeRateOracle(address indexed oldOracle, address indexed newOracle);

    /// @notice Initializes the L2 staked token SY adapter.
    /// @param name_ Token name for the ERC20 representation.
    /// @param symbol_ Token symbol for the ERC20 representation.
    /// @param owner_ Address that will be granted the owner role.
    /// @param token_ The yield-bearing token on L2 (IS the SY — no wrapping needed).
    /// @param exchangeRateOracle_ Oracle that reports the canonical-asset-per-SY exchange rate.
    /// @param underlyingAssetOnEthAddr_ Address of the underlying asset on Ethereum mainnet.
    /// @param underlyingAssetOnEthDecimals_ Decimals of the underlying asset on Ethereum mainnet.
    function initialize(
        string calldata name_,
        string calldata symbol_,
        address owner_,
        address token_,
        address exchangeRateOracle_,
        address underlyingAssetOnEthAddr_,
        uint8 underlyingAssetOnEthDecimals_
    ) external initializer {
        __SYBase_init(name_, symbol_, token_, owner_);
        if (exchangeRateOracle_ == address(0) || underlyingAssetOnEthAddr_ == address(0)) revert SYZeroAddress();
        OutrunL2StakedTokenSYStorage storage $ = _getStorage();
        $.exchangeRateOracle = exchangeRateOracle_;
        $.underlyingAssetOnEthAddr = underlyingAssetOnEthAddr_;
        $.underlyingAssetOnEthDecimals = underlyingAssetOnEthDecimals_;
    }

    function _getStorage() private pure returns (OutrunL2StakedTokenSYStorage storage $) {
        // slither-disable-next-line assembly
        assembly {
            $.slot := OUTRUN_L2_STAKED_TOKEN_SY_STORAGE_LOCATION
        }
    }

    /// @notice Returns the address of the exchange rate oracle.
    /// @return The oracle address that reports the canonical-asset-per-SY exchange rate.
    function exchangeRateOracle() public view returns (address) {
        return _getStorage().exchangeRateOracle;
    }

    /// @notice Updates the exchange rate oracle address. Owner-only.
    /// @param newOracle The new oracle address. Must not be zero.
    function setExchangeRateOracle(address newOracle) external onlyOwner {
        if (newOracle == address(0)) revert SYZeroAddress();
        OutrunL2StakedTokenSYStorage storage $ = _getStorage();
        address oldOracle = $.exchangeRateOracle;
        $.exchangeRateOracle = newOracle;
        emit SetExchangeRateOracle(oldOracle, newOracle);
    }

    /// @notice Adapter-specific deposit logic — 1:1, the yield-bearing token IS the SY.
    function _deposit(address, uint256 amountDeposited) internal pure override returns (uint256) {
        return amountDeposited;
    }

    /// @notice Adapter-specific redeem logic — transfers the yield-bearing token 1:1 to the receiver.
    function _redeem(address receiver, address tokenOut, uint256 amountSharesToRedeem)
        internal
        override
        returns (uint256)
    {
        _transferOut(tokenOut, receiver, amountSharesToRedeem);
        return amountSharesToRedeem;
    }

    /// @notice Returns the current exchange rate from the oracle (not from token balance).
    /// The L2 token balance does not grow with yield, so the oracle reports the canonical
    /// asset amount per SY as tracked on the source chain.
    /// @return The exchange rate, scaled by 1e18.
    function exchangeRate() public view override returns (uint256) {
        return IExchangeRateOracle(exchangeRateOracle()).getExchangeRate();
    }

    /// @notice Adapter-specific preview of a deposit — returns the input amount (1:1, no wrapping).
    function _previewDeposit(address, uint256 amountTokenToDeposit) internal pure override returns (uint256) {
        return amountTokenToDeposit;
    }

    /// @notice Adapter-specific preview of a redemption — returns the input amount (1:1, no unwrapping).
    function _previewRedeem(address, uint256 amountSharesToRedeem) internal pure override returns (uint256) {
        return amountSharesToRedeem;
    }

    /// @notice Returns all tokens accepted for deposit — only the yield-bearing token.
    /// @return res Single-element array containing the yield-bearing token address.
    function getTokensIn() public view override returns (address[] memory res) {
        return ArrayLib.create(yieldBearingToken());
    }

    /// @notice Returns all tokens accepted for redemption — only the yield-bearing token.
    /// @return res Single-element array containing the yield-bearing token address.
    function getTokensOut() public view override returns (address[] memory res) {
        return ArrayLib.create(yieldBearingToken());
    }

    /// @notice Checks whether the given token is accepted for deposit.
    /// @param token The token address to check.
    /// @return True if the token equals the yield-bearing token.
    function isValidTokenIn(address token) public view override returns (bool) {
        return token == yieldBearingToken();
    }

    /// @notice Checks whether the given token is accepted for redemption.
    /// @param token The token address to check.
    /// @return True if the token equals the yield-bearing token.
    function isValidTokenOut(address token) public view override returns (bool) {
        return token == yieldBearingToken();
    }

    /// @notice Reports the underlying asset details on Ethereum mainnet (for position accounting).
    /// @return assetType Always AssetType.TOKEN.
    /// @return assetAddress Address of the underlying asset on Ethereum mainnet.
    /// @return assetDecimals Decimals of the underlying asset on Ethereum mainnet.
    function assetInfo() external view returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        OutrunL2StakedTokenSYStorage storage $ = _getStorage();
        return (AssetType.TOKEN, $.underlyingAssetOnEthAddr, $.underlyingAssetOnEthDecimals);
    }
}
