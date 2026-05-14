//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

interface IWstETH {
    /**
     * @notice Returns the stETH amount represented by one wstETH.
     * @dev OutrunWstETHSY consumes this as its local `exchangeRate()` source.
     * @return The stETH-per-wstETH exchange rate.
     */
    function stEthPerToken() external view returns (uint256);

    /**
     * @notice Quotes wstETH output for a stETH input amount.
     * @dev OutrunWstETHSY consumes this for stETH deposit previews.
     * @param stETHAmount The stETH amount to convert.
     * @return The corresponding wstETH amount.
     */
    function getWstETHByStETH(uint256 stETHAmount) external view returns (uint256);

    /**
     * @notice Quotes stETH output for a wstETH input amount.
     * @dev OutrunWstETHSY consumes this for redemption previews.
     * @param wstETHAmount The wstETH amount to convert.
     * @return The corresponding stETH amount.
     */
    function getStETHByWstETH(uint256 wstETHAmount) external view returns (uint256);

    /**
     * @notice Wraps stETH into wstETH.
     * @dev OutrunWstETHSY calls this after it holds stETH and consumes the return value as minted SY shares.
     * @param stETHAmount The amount of stETH to wrap.
     * @return The amount of wstETH minted.
     */
    function wrap(uint256 stETHAmount) external returns (uint256);

    /**
     * @notice Unwraps wstETH into stETH.
     * @dev OutrunWstETHSY calls this on redemption when stETH is the requested output.
     * @param wstETHAmount The amount of wstETH to unwrap.
     * @return The amount of stETH returned.
     */
    function unwrap(uint256 wstETHAmount) external returns (uint256);
}
