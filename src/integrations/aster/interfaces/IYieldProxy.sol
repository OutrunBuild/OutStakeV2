//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

interface IYieldProxy {
    /**
     * @notice Returns the Lista stake manager wired to the yield proxy.
     * @return The stake manager address.
     */
    function stakeManager() external view returns (address);
}
