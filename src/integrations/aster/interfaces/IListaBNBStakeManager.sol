//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

interface IListaBNBStakeManager {
    /**
     * @notice Quotes the slisBNB output for a native BNB input amount.
     * @dev OutrunAsBNBSY consumes this as a read-only conversion quote before calling the asBNB minter.
     * @param amount The BNB amount to convert.
     * @return The corresponding slisBNB amount.
     */
    function convertBnbToSnBnb(uint256 amount) external view returns (uint256);

    /**
     * @notice Quotes the native BNB output for a slisBNB input amount.
     * @dev OutrunAsBNBSY consumes this to express asBNB value in native BNB terms for `exchangeRate()`.
     * @param amount The slisBNB amount to convert.
     * @return The corresponding BNB amount.
     */
    function convertSnBnbToBnb(uint256 amount) external view returns (uint256);
}
