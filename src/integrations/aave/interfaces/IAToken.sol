// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

interface IAToken {
    /**
     * @notice Returns the underlying asset tracked by this aToken.
     * @dev OutrunAaveV3SY uses this to bind the adapter's underlying token to the aToken reserve address.
     * @return The underlying ERC20 asset address.
     */
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);

    /**
     * @notice Returns a user's balance in scaled units.
     * @dev Local adapters may consume scaled balances with pool income data; this interface does not define the
     * upstream index mechanics.
     * @param user The account to query.
     * @return The scaled balance for `user`.
     */
    function scaledBalanceOf(address user) external view returns (uint256);

    /**
     * @notice Returns a user's scaled balance together with the scaled total supply.
     * @dev Exposed for Aave accounting reads used by integrations; no local freshness or reserve invariant is
     * asserted here.
     * @param user The account to query.
     * @return The user's scaled balance and the current scaled total supply.
     */
    function getScaledUserBalanceAndSupply(address user) external view returns (uint256, uint256);

    /**
     * @notice Returns the total scaled supply of the aToken.
     * @dev Exposed for integration accounting reads before applying any reserve income multiplier.
     * @return The total scaled token supply.
     */
    function scaledTotalSupply() external view returns (uint256);

    /**
     * @notice Returns the previous liquidity index recorded for a user.
     * @dev Exposed for integrations that compare user state against an upstream index.
     * @param user The account to query.
     * @return The previously stored index for `user`.
     */
    function getPreviousIndex(address user) external view returns (uint256);
}
