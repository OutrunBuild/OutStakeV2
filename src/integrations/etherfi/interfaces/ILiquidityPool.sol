//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

interface ILiquidityPool {
    /**
     * @notice Quotes the number of shares represented by an asset amount.
     * @dev This is a read-only conversion helper exposed by the Ether.fi liquidity pool.
     * @param _amount The asset amount to convert.
     * @return The corresponding share amount.
     */
    function sharesForAmount(uint256 _amount) external view returns (uint256);

    /**
     * @notice Quotes the asset amount represented by a share amount.
     * @dev This is a read-only conversion helper exposed by the Ether.fi liquidity pool.
     * @param _share The share amount to convert.
     * @return The corresponding asset amount.
     */
    function amountForShare(uint256 _share) external view returns (uint256);
}
