//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

interface IYieldProxy {
    /**
     * @notice Returns the Lista stake manager wired to the yield proxy.
     * @dev Integrations use this address for BNB and slisBNB conversion quotes.
     * @return The stake manager address.
     */
    function stakeManager() external view returns (address);

    /**
     * @notice Returns whether the yield proxy is processing queued activities.
     * @dev Used to distinguish an async queued state from a true zero-output result.
     * @return Whether async activities are still in progress.
     */
    function activitiesOnGoing() external view returns (bool);
}
