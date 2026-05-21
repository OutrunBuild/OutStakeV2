// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {IExchangeRateOracle} from "./interfaces/IExchangeRateOracle.sol";
import {AggregatorInterface} from "./interfaces/AggregatorInterface.sol";

error InvalidOracleAnswer();

/// @notice Thin adapter that wraps a Chainlink-style oracle (AggregatorInterface) into an IExchangeRateOracle.
/// Normalizes the oracle's raw answer to the target SY decimals.
/// Only validates that the answer is positive; does not enforce freshness or bounds checks.
contract OutrunExchangeOracleAdapter is IExchangeRateOracle {
    /// @notice The underlying Chainlink-style price feed that provides the raw exchange rate answer.
    /// @return The address of the Chainlink-style oracle.
    address public immutable oracle;
    /// @notice Target decimals for the normalized output (matches the SY's canonical asset decimals).
    /// @return The number of decimals for the normalized output.
    uint8 public immutable decimals;
    /// @notice The underlying oracle's native decimal precision (captured once at construction).
    /// @return The number of decimals the underlying oracle reports in.
    uint8 public immutable rawDecimals;

    /// @notice Sets the underlying Chainlink-style oracle and captures its native decimal precision once at construction.
    /// @param _oracle The address of the Chainlink-style price feed (AggregatorInterface).
    /// @param _decimals The target number of decimals for the normalized output.
    /// @dev Captures raw oracle decimals at construction. If the underlying oracle later changes its decimals
    /// (which Chainlink does not), this adapter won't track the change — that's by design for simplicity.
    constructor(address _oracle, uint8 _decimals) {
        oracle = _oracle;
        decimals = _decimals;
        rawDecimals = AggregatorInterface(_oracle).decimals();
    }

    /**
     * @notice Returns the latest oracle exchange rate scaled to the configured SY decimals.
     * @dev Reverts when the underlying oracle answer is non-positive. Does not apply freshness checks,
     * bounds checks, or fallback oracle logic.
     * @return The normalized exchange rate value.
     */
    function getExchangeRate() external view returns (uint256) {
        // Step 1: Read the raw oracle answer (int256, can be negative for error states).
        int256 answer = AggregatorInterface(oracle).latestAnswer();
        // Step 2: Reject non-positive answers (zero or negative = oracle error).
        if (answer <= 0) revert InvalidOracleAnswer();
        // Step 3: Normalize: (rawAnswer * 10^targetDecimals) / 10^rawDecimals.
        // Example: raw=1.05e8 (8 decimals), target=18 decimals -> 1.05e18 / 1e8 * 1e18 -> 1.05e18.
        // forge-lint: disable-next-line(unsafe-typecast)
        return (uint256(answer) * 10 ** decimals) / 10 ** rawDecimals;
    }
}
