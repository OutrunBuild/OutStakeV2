// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {OutrunOFT} from "../omnichain/OutrunOFT.sol";
import {IUniversalAssets} from "../interfaces/IUniversalAssets.sol";

/**
 * @dev Outrun Universal Assets
 */
contract OutrunUniversalAssets is IUniversalAssets, OutrunOFT {
    mapping(address minter => MintingStatus) public mintingStatusTable;

    constructor(string memory _name, string memory _symbol, uint8 _decimals, address _lzEndpoint, address _owner)
        OutrunOFT(_name, _symbol, _decimals, _lzEndpoint, _owner)
        Ownable(_owner)
    {}

    /**
     * @notice Returns the remaining minting allowance for a minter.
     * @dev Computes the allowance from the minter's configured cap and minted amount.
     * @param minter Address whose minting allowance is queried.
     * @return amountInMintable Remaining amount the minter can still mint.
     */
    function checkMintableAmount(address minter) external view override returns (uint256 amountInMintable) {
        MintingStatus storage status = mintingStatusTable[minter];
        uint256 mintingCap = status.mintingCap;
        uint256 amountInMinted = status.amountInMinted;
        amountInMintable = mintingCap > amountInMinted ? mintingCap - amountInMinted : 0;
    }

    /**
     * @notice Sets the minting cap for a minter.
     * @dev Only the contract owner can update per-minter caps.
     * @param minter Address whose cap is updated.
     * @param mintingCap New minting cap assigned to the minter.
     */
    function setMintingCap(address minter, uint256 mintingCap) public override onlyOwner {
        require(minter != address(0), ZeroInput());

        uint256 oldMintingCap = mintingStatusTable[minter].mintingCap;
        mintingStatusTable[minter].mintingCap = mintingCap;

        emit SetMintingCap(minter, oldMintingCap, mintingCap);
    }

    /**
     * @notice Revokes a minter by clearing its minting cap.
     * @dev Only the contract owner can revoke minting permission in this way.
     * @param minter Address whose minting permission is revoked.
     */
    function revokeMinter(address minter) external override onlyOwner {
        require(minter != address(0), ZeroInput());

        uint256 oldMintingCap = mintingStatusTable[minter].mintingCap;
        mintingStatusTable[minter].mintingCap = 0;

        emit RevokeMinter(minter, oldMintingCap);
    }

    /**
     * @notice Mints uAsset to a receiver using the caller's remaining minting capacity.
     * @dev Reverts when the receiver is zero, the amount is zero, or the caller would exceed its cap.
     * @param receiver - Address of uAsset receiver
     * @param amount - Amount of uAsset
     */
    function mint(address receiver, uint256 amount) external override whenNotPaused {
        require(amount != 0 && receiver != address(0), ZeroInput());

        uint256 mintingCap = mintingStatusTable[msg.sender].mintingCap;
        uint256 amountInMinted = mintingStatusTable[msg.sender].amountInMinted;
        require(amountInMinted + amount <= mintingCap, ReachMintCap());

        mintingStatusTable[msg.sender].amountInMinted += amount;
        _mint(receiver, amount);

        emit MintUAsset(msg.sender, receiver, amount);
    }

    /**
     * @notice Repays the caller's own minted debt using uAsset held by an account.
     * @dev `msg.sender` is always the debt owner whose outstanding minted amount is reduced.
     *      The repayment path always consumes allowance from `account` to `msg.sender`.
     * @param account Address whose uAsset balance is burned.
     * @param amount Amount of uAsset repaid.
     */
    function repay(address account, uint256 amount) external override {
        uint256 amountInMinted = mintingStatusTable[msg.sender].amountInMinted;
        require(amountInMinted >= amount, ReachBurnCap());

        if (account != msg.sender) _spendAllowance(account, msg.sender, amount);
        _burn(account, amount);

        mintingStatusTable[msg.sender].amountInMinted = amountInMinted - amount;

        emit BurnUAsset(msg.sender, amount);
    }
}
