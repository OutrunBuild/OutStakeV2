// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

/**
 * @title MemeverseLauncher interface
 * @notice External launcher surface consumed by OutrunRouter genesis flows.
 */
interface IMemeverseLauncher {
    /**
     * @notice Launches a verse genesis flow using newly minted uAsset.
     * @dev OutrunRouter approves and calls this after creating a locked position that minted uAsset to the
     * router. This interface records only the local call boundary, not launcher-side accounting rules.
     * @param verseId Memeverse verse identifier to launch against.
     * @param amountInUAsset Amount of uAsset committed to genesis.
     * @param user User credited for the genesis action.
     */
    function genesis(uint256 verseId, uint128 amountInUAsset, address user) external;
}
