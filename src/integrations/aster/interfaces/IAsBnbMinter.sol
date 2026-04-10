//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

interface IAsBnbMinter {
    /**
     * @notice Returns the asBNB token wired to the minter.
     * @dev The upstream implementation exposes this as a public state variable getter.
     * @return The asBNB token address.
     */
    function asBnb() external view returns (address);

    /**
     * @notice Returns the slisBNB token accepted by the minter.
     * @dev The upstream implementation exposes this as a public state variable getter.
     * @return The slisBNB token address.
     */
    function token() external view returns (address);

    /**
     * @notice Returns the yield proxy used by the minter.
     * @dev The upstream implementation exposes this as a public state variable getter.
     * @return The yield proxy address.
     */
    function yieldProxy() external view returns (address);

    /**
     * @notice Mints asBNB from slisBNB.
     * @param amountIn The slisBNB amount to deposit.
     * @return The asBNB amount minted, or zero when Aster queues the request.
     */
    function mintAsBnb(uint256 amountIn) external returns (uint256);

    /**
     * @notice Mints asBNB from native BNB.
     * @return The asBNB amount minted, or zero when Aster queues the request.
     */
    function mintAsBnb() external payable returns (uint256);

    /**
     * @notice Quotes the token-side asset value represented by an asBNB amount.
     * @param asBNBAmount The asBNB amount to convert.
     * @return The corresponding token-side amount.
     */
    function convertToTokens(uint256 asBNBAmount) external view returns (uint256);

    /**
     * @notice Quotes the asBNB amount represented by a token-side amount.
     * @param tokenAmount The token-side amount to convert.
     * @return The corresponding asBNB amount.
     */
    function convertToAsBnb(uint256 tokenAmount) external view returns (uint256);
}
