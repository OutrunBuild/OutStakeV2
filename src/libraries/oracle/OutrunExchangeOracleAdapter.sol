// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {IExchangeRateOracle} from "./interfaces/IExchangeRateOracle.sol";
import {AggregatorInterface} from "./interfaces/AggregatorInterface.sol";

/// @notice Thin adapter that wraps a Chainlink-style oracle (AggregatorInterface) into an IExchangeRateOracle.
/// Normalizes the oracle's raw answer to the target SY decimals.
/// Validates that the answer is positive and updated within the configured staleness window.
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
    /// @notice Maximum age allowed for the latest oracle answer.
    /// @return The staleness threshold in seconds.
    uint256 public immutable maxStaleness;
    /// @notice Optional Chainlink L2 Sequencer Uptime Feed. Zero address disables this check.
    /// @return The sequencer uptime feed address.
    address public immutable sequencerUptimeFeed;
    /// @notice Time to wait after the sequencer comes back up before trusting oracle answers.
    /// @return The grace period in seconds.
    uint256 public immutable sequencerGracePeriod;

    /// @notice Sets the underlying Chainlink-style oracle and captures its native decimal precision once at construction.
    /// @param _oracle The address of the Chainlink-style price feed (AggregatorInterface).
    /// @param _decimals The target number of decimals for the normalized output.
    /// @param _maxStaleness Maximum allowed age for `latestRoundData().updatedAt`.
    /// @param _sequencerUptimeFeed Optional Chainlink L2 Sequencer Uptime Feed; zero address disables this check.
    /// @param _sequencerGracePeriod Grace period after sequencer recovery before oracle answers are trusted.
    /// @dev Captures raw oracle decimals at construction. If the underlying oracle later changes its decimals
    /// (which Chainlink does not), this adapter won't track the change — that's by design for simplicity.
    constructor(
        address _oracle,
        uint8 _decimals,
        uint256 _maxStaleness,
        address _sequencerUptimeFeed,
        uint256 _sequencerGracePeriod
    ) {
        oracle = _oracle;
        decimals = _decimals;
        maxStaleness = _maxStaleness;
        sequencerUptimeFeed = _sequencerUptimeFeed;
        sequencerGracePeriod = _sequencerGracePeriod;
        rawDecimals = AggregatorInterface(_oracle).decimals();
    }

    /**
     * @notice Returns the latest oracle exchange rate scaled to the configured SY decimals.
     * @dev Reverts when the underlying oracle answer is non-positive or stale. Does not apply bounds checks,
     * fallback oracle logic, or multi-source aggregation.
     * @return The normalized exchange rate value.
     */
    function getExchangeRate() external view returns (uint256) {
        _validateSequencer();
        // Chainlink-style feeds expose update time only through latestRoundData().
        (, int256 answer,, uint256 updatedAt,) = AggregatorInterface(oracle).latestRoundData();
        if (answer <= 0) revert InvalidOracleAnswer();
        if (updatedAt == 0 || block.timestamp - updatedAt > maxStaleness) revert StaleOracleAnswer();
        // Normalize: (rawAnswer * 10^targetDecimals) / 10^rawDecimals.
        // Example: raw=1.05e8 (8 decimals), target=18 decimals -> 1.05e18 / 1e8 * 1e18 -> 1.05e18.
        // forge-lint: disable-next-line(unsafe-typecast)
        return (uint256(answer) * 10 ** decimals) / 10 ** rawDecimals;
    }

    function _validateSequencer() internal view {
        address _sequencerUptimeFeed = sequencerUptimeFeed;
        if (_sequencerUptimeFeed == address(0)) return;

        (, int256 answer, uint256 startedAt,,) = AggregatorInterface(_sequencerUptimeFeed).latestRoundData();
        if (answer != 0) revert SequencerDown();
        if (startedAt == 0 || startedAt > block.timestamp) revert SequencerGracePeriodNotOver();
        if (block.timestamp - startedAt <= sequencerGracePeriod) revert SequencerGracePeriodNotOver();
    }
}
