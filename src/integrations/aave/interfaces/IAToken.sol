// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IAToken {
    /**
     * @notice Returns the underlying asset tracked by this aToken.
     * @dev Exposes the reserve asset address configured by the upstream Aave deployment.
     * @return The underlying ERC20 asset address.
     */
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);

    /**
     * @notice Returns a user's balance in scaled units.
     * @dev The scaled balance is the principal-like amount before applying normalized income.
     * @param user The account to query.
     * @return The scaled balance for `user`.
     */
    function scaledBalanceOf(address user) external view returns (uint256);

    /**
     * @notice Returns a user's scaled balance together with the scaled total supply.
     * @dev This mirrors the upstream Aave helper used by integrations for accounting reads.
     * @param user The account to query.
     * @return The user's scaled balance and the current scaled total supply.
     */
    function getScaledUserBalanceAndSupply(address user) external view returns (uint256, uint256);

    /**
     * @notice Returns the total scaled supply of the aToken.
     * @dev The scaled supply omits the current reserve income multiplier.
     * @return The total scaled token supply.
     */
    function scaledTotalSupply() external view returns (uint256);

    /**
     * @notice Returns the previous liquidity index recorded for a user.
     * @dev Integrations can use this to compare the user's last accounted Aave index.
     * @param user The account to query.
     * @return The previously stored index for `user`.
     */
    function getPreviousIndex(address user) external view returns (uint256);
}
