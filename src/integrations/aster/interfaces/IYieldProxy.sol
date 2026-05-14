//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

interface IYieldProxy {
    /**
     * @notice Returns the Lista stake manager wired to the yield proxy.
     * @dev OutrunAsBNBSY reads this during setup and then consumes the stake manager's conversion quote methods.
     * @return The stake manager address.
     */
    function stakeManager() external view returns (address);

    /**
     * @notice Returns whether the yield proxy is processing queued activities.
     * @dev OutrunAsBNBSY checks this after a zero mint result to classify the local deposit as queued.
     * @return Whether async activities are still in progress.
     */
    function activitiesOnGoing() external view returns (bool);
}
