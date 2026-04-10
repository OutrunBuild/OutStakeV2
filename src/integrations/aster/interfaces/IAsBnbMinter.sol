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
     * @dev Returns zero when the request is queued by Aster instead of settled immediately.
     * @param amountIn The slisBNB amount to deposit.
     * @return The asBNB amount minted, or zero when Aster queues the request.
     */
    function mintAsBnb(uint256 amountIn) external returns (uint256);

    /**
     * @notice Mints asBNB from native BNB.
     * @dev msg.value is the BNB deposit; returns zero when queued by Aster.
     * @return The asBNB amount minted, or zero when Aster queues the request.
     */
    function mintAsBnb() external payable returns (uint256);

    /**
     * @notice Quotes the token-side asset value represented by an asBNB amount.
     * @dev Converts asBNB to the equivalent slisBNB amount at the current exchange rate.
     * @param asBNBAmount The asBNB amount to convert.
     * @return The corresponding token-side amount.
     */
    function convertToTokens(uint256 asBNBAmount) external view returns (uint256);

    /**
     * @notice Quotes the asBNB amount represented by a token-side amount.
     * @dev Converts slisBNB to the equivalent asBNB amount at the current exchange rate.
     * @param tokenAmount The token-side amount to convert.
     * @return The corresponding asBNB amount.
     */
    function convertToAsBnb(uint256 tokenAmount) external view returns (uint256);
}
