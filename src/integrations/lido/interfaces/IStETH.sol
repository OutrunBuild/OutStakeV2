//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

interface IStETH {
    /**
     * @notice Quotes shares for a pooled ETH amount.
     * @dev This helper exposes the current stETH share conversion.
     * @param ethAmount The pooled ETH amount to convert.
     * @return The corresponding share amount.
     */
    function getSharesByPooledEth(uint256 ethAmount) external view returns (uint256);

    /**
     * @notice Quotes pooled ETH for a share amount.
     * @dev This helper exposes the current stETH share redemption conversion.
     * @param shareAmount The share amount to convert.
     * @return The corresponding pooled ETH amount.
     */
    function getPooledEthByShares(uint256 shareAmount) external view returns (uint256);

    /**
     * @notice Stakes native ETH into stETH.
     * @dev The referral address is forwarded to the upstream Lido submit path.
     * @param referral The referral address supplied to Lido.
     * @return The share amount minted by the submit call.
     */
    function submit(address referral) external payable returns (uint256);
}
