// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.35;

/**
 * @title Outrun omnichain universal assets interface
 * @notice uAsset exposes a minter-scoped debt token surface for position and wrap accounting.
 */
interface IUniversalAssets {
    /**
     * @notice Minting state for one minter address.
     * @dev `mintingCap` is the minter's configured ceiling; `amountInMinted` is that minter's outstanding
     * debt after mints minus repayments. The table is not a global debt pool.
     */
    struct MintingStatus {
        uint256 mintingCap;
        uint256 amountInMinted;
    }

    /**
     * @notice Returns the remaining uAsset minting allowance for a minter.
     * @dev Computes `max(mintingCap - amountInMinted, 0)` for the queried minter.
     * @param minter Address whose minting capacity is being queried.
     * @return amountInMintable Remaining amount the minter can mint.
     */
    function checkMintableAmount(address minter) external view returns (uint256 amountInMintable);

    /**
     * @notice Sets the minting cap for a minter.
     * @dev Owner-controlled configuration. Updating the cap changes only future mint headroom; it does not
     * rewrite `amountInMinted`.
     * @param minter Address whose cap is updated.
     * @param mintingCap New minting cap assigned to the minter.
     */
    function setMintingCap(address minter, uint256 mintingCap) external;

    /**
     * @notice Revokes minting permission by clearing a minter's cap.
     * @dev Sets `mintingCap` to zero. Existing `amountInMinted` remains outstanding until the minter repays.
     * @param minter Address whose minting permission is revoked.
     */
    function revokeMinter(address minter) external;

    /**
     * @notice Transfers outstanding minted debt from one minter record to another.
     * @dev Owner-only debt accounting operation. Does not mint, burn, transfer, or change total supply.
     * `from` and `to` must be nonzero, distinct minter records.
     * @param from Minter whose outstanding debt is decreased.
     * @param to Minter whose outstanding debt is increased.
     * @param amount Amount of outstanding debt to transfer.
     */
    function transferMinterDebt(address from, address to, uint256 amount) external;

    /**
     * @notice Mints uAsset to a receiver using the caller's minting allowance.
     * @dev `msg.sender` is the minter whose `amountInMinted` increases and whose cap is checked.
     * @param receiver Address receiving the minted uAsset.
     * @param amount Amount of uAsset to mint.
     */
    function mint(address receiver, uint256 amount) external;

    /**
     * @notice Repays the caller's own minted debt using uAsset held by an account.
     * @dev `msg.sender` is the minter whose `amountInMinted` decreases. `account` is the balance burned; when
     * `account != msg.sender`, the caller must have allowance to burn `account`'s uAsset.
     * @param account Address whose uAsset balance is burned.
     * @param amount Amount of uAsset to burn.
     */
    function repay(address account, uint256 amount) external;

    event MintUAsset(address indexed minter, address indexed receiver, uint256 amount);

    event BurnUAsset(address indexed minter, uint256 amount);

    event SetMintingCap(address indexed minter, uint256 oldMintingCap, uint256 newMintingCap);

    event RevokeMinter(address indexed minter, uint256 oldMintingCap);

    event TransferMinterDebt(address indexed from, address indexed to, uint256 amount);

    error ZeroInput();

    error ReachMintCap();

    error ReachBurnCap();
}
