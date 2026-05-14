// SPDX-FileCopyrightText: 2024 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

interface IL2StETH {
    /**
     * @notice Wraps the underlying L2 token into the wrapper token.
     * @dev This mirrors the upstream L2 wrapper entrypoint exposed by Lido.
     * @param wrappableTokenAmount The amount of underlying token to wrap.
     * @return The amount of wrapped token minted.
     */
    function wrap(uint256 wrappableTokenAmount) external returns (uint256);

    /**
     * @notice Unwraps the wrapper token back into the underlying L2 token.
     * @dev This mirrors the upstream L2 wrapper exitpoint exposed by Lido.
     * @param wrapperTokenAmount The amount of wrapped token to burn.
     * @return The amount of underlying token returned.
     */
    function unwrap(uint256 wrapperTokenAmount) external returns (uint256);

    /**
     * @notice Quotes token amount for a share amount.
     * @dev This helper exposes the wrapper's share-to-token conversion.
     * @param sharesAmount The amount of shares to convert.
     * @return The corresponding token amount.
     */
    function getTokensByShares(uint256 sharesAmount) external view returns (uint256);

    /**
     * @notice Quotes share amount for a token amount.
     * @dev This helper exposes the wrapper's token-to-share conversion.
     * @param tokenAmount The amount of tokens to convert.
     * @return The corresponding share amount.
     */
    function getSharesByTokens(uint256 tokenAmount) external view returns (uint256);
}
