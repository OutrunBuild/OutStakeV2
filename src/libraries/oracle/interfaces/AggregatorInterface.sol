// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.35;

// solhint-disable-next-line interface-starts-with-i
interface AggregatorInterface {
    /// @notice Return the number of decimals used by the answer.
    /// @dev OutrunExchangeOracleAdapter reads this once to normalize `latestRoundData().answer`.
    /// @return The decimals used to scale answer values.
    function decimals() external view returns (uint8);

    /// @notice Return the aggregator description string.
    /// @dev Exposes the human-readable identifier published by the feed.
    /// @return The description string for this aggregator.
    function description() external view returns (string memory);

    /// @notice Return the aggregator implementation version.
    /// @dev Exposes the version number reported by the feed contract.
    /// @return The current aggregator version.
    function version() external view returns (uint256);

    /// @notice Return the most recent answer.
    /// @dev OutrunExchangeOracleAdapter consumes this value only; freshness, bounds, and fallback checks are not
    ///      declared by this interface.
    /// @return The most recent answer value.
    function latestAnswer() external view returns (int256);

    /// @notice Return the timestamp for the latest answer.
    /// @dev This is the legacy timestamp accessor retained for compatibility.
    /// @return The timestamp of the latest reported answer.
    function latestTimestamp() external view returns (uint256);

    /// @notice Return the latest round identifier.
    /// @dev This is the legacy round accessor retained for compatibility.
    /// @return The latest round id.
    function latestRound() external view returns (uint256);

    /// @notice Return the answer recorded for a given round.
    /// @dev Returns the stored answer for an already reported round.
    /// @param roundId Round identifier to query.
    /// @return The answer associated with `roundId`.
    function getAnswer(uint256 roundId) external view returns (int256);

    /// @notice Return the timestamp recorded for a given round.
    /// @dev Returns the stored update timestamp for an already reported round.
    /// @param roundId Round identifier to query.
    /// @return The timestamp associated with `roundId`.
    function getTimestamp(uint256 roundId) external view returns (uint256);

    /// @notice Return round data for a specific round.
    /// @dev Returns the full round tuple for the requested historical round id.
    /// @param _roundId Round identifier to query.
    /// @return roundId The round id returned by the aggregator.
    /// @return answer The answer reported for the round.
    /// @return startedAt The timestamp when the round started.
    /// @return updatedAt The timestamp when the answer was updated.
    /// @return answeredInRound The round in which the answer was computed.
    function getRoundData(uint80 _roundId)
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

    /// @notice Return round data for the latest round.
    /// @dev OutrunExchangeOracleAdapter consumes `answer` and `updatedAt` from this tuple.
    /// @return roundId The latest round id.
    /// @return answer The latest answer value.
    /// @return startedAt The timestamp when the latest round started.
    /// @return updatedAt The timestamp when the latest answer was updated.
    /// @return answeredInRound The round in which the latest answer was computed.
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}
