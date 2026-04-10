// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

interface IListaStakeManager {
    /// @notice Stakes native BNB and mints slisBNB to the caller.
    /// @dev Unlike WETH.deposit(), this mints a yield-bearing token with a floating exchange rate.
    ///      Returns void; actual mint amount must be measured via slisBNB balance diff.
    function deposit() external payable;

    /// @notice Requests an asynchronous withdrawal (7-day unbonding).
    /// @dev Not used by OutrunSlisBNBSY — included for interface completeness.
    function requestWithdraw(uint256 amountInSnBnb) external;

    /// @notice Claims a completed withdrawal request.
    function claimWithdraw(uint256 idx) external;

    /// @notice Quotes the slisBNB output for a given BNB input.
    function convertBnbToSnBnb(uint256 amount) external view returns (uint256);

    /// @notice Quotes the BNB value of a given slisBNB amount.
    function convertSnBnbToBnb(uint256 amount) external view returns (uint256);

    /// @notice Returns the total pooled BNB across all stakers.
    function getTotalPooledBnb() external view returns (uint256);
}
