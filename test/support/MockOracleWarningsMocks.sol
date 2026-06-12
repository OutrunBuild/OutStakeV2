// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.35;

contract MockAggregator {
    int256 internal latestOracleAnswer;
    uint256 internal latestOracleUpdatedAt;
    uint256 internal latestOracleStartedAt;

    function setLatestAnswer(int256 answer) external {
        latestOracleAnswer = answer;
        latestOracleStartedAt = block.timestamp;
        latestOracleUpdatedAt = block.timestamp;
    }

    function setLatestRoundData(int256 answer, uint256 updatedAt) external {
        latestOracleAnswer = answer;
        latestOracleStartedAt = updatedAt;
        latestOracleUpdatedAt = updatedAt;
    }

    function setLatestRoundData(int256 answer, uint256 startedAt, uint256 updatedAt) external {
        latestOracleAnswer = answer;
        latestOracleStartedAt = startedAt;
        latestOracleUpdatedAt = updatedAt;
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function description() external pure returns (string memory) {
        return "mock";
    }

    function version() external pure returns (uint256) {
        return 1;
    }

    function latestAnswer() external view returns (int256) {
        return latestOracleAnswer;
    }

    function latestTimestamp() external view returns (uint256) {
        return latestOracleUpdatedAt;
    }

    function latestRound() external pure returns (uint256) {
        return 1;
    }

    function getAnswer(uint256) external view returns (int256) {
        return latestOracleAnswer;
    }

    function getTimestamp(uint256) external view returns (uint256) {
        return latestOracleUpdatedAt;
    }

    function getRoundData(uint80)
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (1, latestOracleAnswer, latestOracleStartedAt, latestOracleUpdatedAt, 1);
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (1, latestOracleAnswer, latestOracleStartedAt, latestOracleUpdatedAt, 1);
    }
}
