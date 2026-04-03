//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

interface IWeETH {
    /**
     * @notice Wraps eETH into weETH.
     * @dev The caller must supply the eETH amount expected by the upstream wrapper contract.
     * @param _eETHAmount The amount of eETH to wrap.
     * @return The amount of weETH minted.
     */
    function wrap(uint256 _eETHAmount) external returns (uint256);

    /**
     * @notice Unwraps weETH into eETH.
     * @dev The caller burns weETH and receives the corresponding eETH amount.
     * @param _weETHAmount The amount of weETH to unwrap.
     * @return The amount of eETH returned.
     */
    function unwrap(uint256 _weETHAmount) external returns (uint256);
}
