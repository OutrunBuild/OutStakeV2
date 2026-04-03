//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

interface IWstETH {
    /**
     * @notice Returns the stETH amount represented by one wstETH.
     * @dev This is the wrapper's current exchange rate helper.
     * @return The stETH-per-wstETH exchange rate.
     */
    function stEthPerToken() external view returns (uint256);

    /**
     * @notice Quotes wstETH output for a stETH input amount.
     * @dev This is a read-only conversion helper on the upstream wrapper.
     * @param stETHAmount The stETH amount to convert.
     * @return The corresponding wstETH amount.
     */
    function getWstETHByStETH(uint256 stETHAmount) external view returns (uint256);

    /**
     * @notice Quotes stETH output for a wstETH input amount.
     * @dev This is a read-only conversion helper on the upstream wrapper.
     * @param wstETHAmount The wstETH amount to convert.
     * @return The corresponding stETH amount.
     */
    function getStETHByWstETH(uint256 wstETHAmount) external view returns (uint256);

    /**
     * @notice Wraps stETH into wstETH.
     * @dev The caller must provide the stETH amount expected by the upstream wrapper.
     * @param stETHAmount The amount of stETH to wrap.
     * @return The amount of wstETH minted.
     */
    function wrap(uint256 stETHAmount) external returns (uint256);

    /**
     * @notice Unwraps wstETH into stETH.
     * @dev The caller burns wstETH and receives the corresponding stETH amount.
     * @param wstETHAmount The amount of wstETH to unwrap.
     * @return The amount of stETH returned.
     */
    function unwrap(uint256 wstETHAmount) external returns (uint256);
}
