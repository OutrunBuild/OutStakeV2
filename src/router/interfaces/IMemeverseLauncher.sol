// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

/**
 * @title MemeverseLauncher interface
 */
interface IMemeverseLauncher {
    /**
     * @notice Launches a verse genesis flow using newly minted uAsset.
     * @dev Consumes the supplied uAsset amount as the launcher-side genesis contribution for `user`.
     * @param verseId Memeverse verse identifier to launch against.
     * @param amountInUAsset Amount of uAsset committed to genesis.
     * @param user User credited for the genesis action.
     */
    function genesis(uint256 verseId, uint128 amountInUAsset, address user) external;
}
