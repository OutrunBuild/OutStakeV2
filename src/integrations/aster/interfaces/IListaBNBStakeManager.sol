//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

interface IListaBNBStakeManager {
    /**
     * @notice Quotes the slisBNB output for a native BNB input amount.
     * @param amount The BNB amount to convert.
     * @return The corresponding slisBNB amount.
     */
    function convertBnbToSnBnb(uint256 amount) external view returns (uint256);
}
