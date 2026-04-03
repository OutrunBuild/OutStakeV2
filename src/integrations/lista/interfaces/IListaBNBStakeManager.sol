//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

interface IListaBNBStakeManager {
    /**
     * @notice Stakes native BNB into the Lista stake manager.
     * @dev The exact staking side effects are delegated to the upstream Lista contract.
     */
    function deposit() external payable;

    /**
     * @notice Quotes slisBNB output for a BNB input amount.
     * @dev This is a read-only conversion helper exposed by the Lista stake manager.
     * @param _amount The BNB amount to convert.
     * @return The corresponding slisBNB amount.
     */
    function convertBnbToSnBnb(uint256 _amount) external view returns (uint256);

    /**
     * @notice Quotes BNB output for a slisBNB input amount.
     * @dev This is a read-only conversion helper exposed by the Lista stake manager.
     * @param _amountInSlisBnb The slisBNB amount to convert.
     * @return The corresponding BNB amount.
     */
    function convertSnBnbToBnb(uint256 _amountInSlisBnb) external view returns (uint256);
}
