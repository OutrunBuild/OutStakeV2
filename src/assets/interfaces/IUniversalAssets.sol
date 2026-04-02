// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

/**
 * @title Outrun omnichain universal assets interface
 */
interface IUniversalAssets {
    struct MintingStatus {
        uint256 mintingCap;
        uint256 amountInMinted;
    }

    /**
     * @notice Returns the remaining uAsset minting allowance for a minter.
     * @dev Computes the allowance from the minter's configured cap and minted amount.
     * @param minter Address whose minting capacity is being queried.
     * @return amountInMintable Remaining amount the minter can mint.
     */
    function checkMintableAmount(address minter) external view returns (uint256 amountInMintable);

    /**
     * @notice Sets the minting cap for a minter.
     * @dev Updating the cap changes how much additional uAsset the minter may issue.
     * @param minter Address whose cap is updated.
     * @param mintingCap New minting cap assigned to the minter.
     */
    function setMintingCap(address minter, uint256 mintingCap) external;

    /**
     * @notice Revokes minting permission by clearing a minter's cap.
     * @dev Existing minted debt is not burned by this operation.
     * @param minter Address whose minting permission is revoked.
     */
    function revokeMinter(address minter) external;

    /**
     * @notice Mints uAsset to a receiver using the caller's minting allowance.
     * @dev Implementations are expected to enforce caller-specific mint caps.
     * @param receiver Address receiving the minted uAsset.
     * @param amount Amount of uAsset to mint.
     */
    function mint(address receiver, uint256 amount) external;

    /**
     * @notice Repays the caller's own minted debt using uAsset held by an account.
     * @dev The caller is always treated as the debt owner/minter whose outstanding debt is reduced.
     * @param account Address whose uAsset balance is burned.
     * @param amount Amount of uAsset to burn.
     */
    function repay(address account, uint256 amount) external;

    event MintUAsset(address indexed minter, address indexed receiver, uint256 amount);

    event BurnUAsset(address indexed minter, uint256 amount);

    event SetMintingCap(address indexed minter, uint256 oldMintingCap, uint256 newMintingCap);

    event RevokeMinter(address indexed minter, uint256 oldMintingCap);

    error ZeroInput();

    error ReachMintCap();

    error ReachBurnCap();
}
