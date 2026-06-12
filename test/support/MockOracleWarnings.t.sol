// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";

import {MockAUSDCOracle} from "./MockAUSDCOracle.sol";
import {MockSUSDSOracle} from "./MockSUSDSOracle.sol";
import {OutrunExchangeOracleAdapter} from "../../src/libraries/oracle/OutrunExchangeOracleAdapter.sol";

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

contract MockOracleWarningsTest is Test {
    bytes4 internal constant INVALID_ORACLE_ANSWER_SELECTOR = bytes4(keccak256("InvalidOracleAnswer()"));
    bytes4 internal constant STALE_ORACLE_ANSWER_SELECTOR = bytes4(keccak256("StaleOracleAnswer()"));
    bytes4 internal constant SEQUENCER_DOWN_SELECTOR = bytes4(keccak256("SequencerDown()"));
    bytes4 internal constant SEQUENCER_GRACE_PERIOD_NOT_OVER_SELECTOR =
        bytes4(keccak256("SequencerGracePeriodNotOver()"));

    address internal owner = address(0xA11CE);

    MockSUSDSOracle internal susdsOracle;
    MockAUSDCOracle internal ausdcOracle;
    MockAggregator internal aggregator;
    MockAggregator internal sequencerUptimeFeed;
    OutrunExchangeOracleAdapter internal adapter;

    function setUp() external {
        susdsOracle = new MockSUSDSOracle(owner);
        ausdcOracle = new MockAUSDCOracle(owner);
        aggregator = new MockAggregator();
        sequencerUptimeFeed = new MockAggregator();
        adapter = new OutrunExchangeOracleAdapter(address(aggregator), 18, 2 days, address(0), 0);
    }

    function testMockSUSDSOracleRevertsWhenAnswerIsZeroOrNegative() external {
        vm.startPrank(owner);

        susdsOracle.setLatestAnswer(0);
        vm.expectRevert();
        susdsOracle.getExchangeRate();

        susdsOracle.setLatestAnswer(-1);
        vm.expectRevert();
        susdsOracle.getExchangeRate();

        vm.stopPrank();
    }

    function testMockAUSDCOracleRevertsWhenAnswerIsZeroOrNegative() external {
        vm.startPrank(owner);

        ausdcOracle.setLatestAnswer(0);
        vm.expectRevert();
        ausdcOracle.getExchangeRate();

        ausdcOracle.setLatestAnswer(-1);
        vm.expectRevert();
        ausdcOracle.getExchangeRate();

        vm.stopPrank();
    }

    function testExchangeOracleAdapterRevertsWhenAnswerIsZeroOrNegative() external {
        aggregator.setLatestAnswer(0);
        vm.expectRevert(INVALID_ORACLE_ANSWER_SELECTOR);
        adapter.getExchangeRate();

        aggregator.setLatestAnswer(-1);
        vm.expectRevert(INVALID_ORACLE_ANSWER_SELECTOR);
        adapter.getExchangeRate();
    }

    function testExchangeOracleAdapterRevertsWhenLatestRoundDataIsStale() external {
        vm.warp(10 days);
        aggregator.setLatestRoundData(1.1 ether, block.timestamp - 2 days - 1);

        vm.expectRevert(STALE_ORACLE_ANSWER_SELECTOR);
        adapter.getExchangeRate();
    }

    function testExchangeOracleAdapterRevertsWhenSequencerIsDown() external {
        adapter =
            new OutrunExchangeOracleAdapter(address(aggregator), 18, 2 days, address(sequencerUptimeFeed), 1 hours);
        aggregator.setLatestAnswer(1.1 ether);
        sequencerUptimeFeed.setLatestAnswer(1);

        vm.expectRevert(SEQUENCER_DOWN_SELECTOR);
        adapter.getExchangeRate();
    }

    function testExchangeOracleAdapterRevertsDuringSequencerGracePeriod() external {
        adapter =
            new OutrunExchangeOracleAdapter(address(aggregator), 18, 2 days, address(sequencerUptimeFeed), 1 hours);
        vm.warp(10 days);
        aggregator.setLatestAnswer(1.1 ether);
        sequencerUptimeFeed.setLatestRoundData(0, block.timestamp - 30 minutes, block.timestamp - 30 minutes);

        vm.expectRevert(SEQUENCER_GRACE_PERIOD_NOT_OVER_SELECTOR);
        adapter.getExchangeRate();
    }

    function testExchangeOracleAdapterRevertsWhenSequencerStartedAtIsZero() external {
        adapter =
            new OutrunExchangeOracleAdapter(address(aggregator), 18, 2 days, address(sequencerUptimeFeed), 1 hours);
        vm.warp(10 days);
        aggregator.setLatestAnswer(1.1 ether);
        sequencerUptimeFeed.setLatestRoundData(0, 0, block.timestamp);

        vm.expectRevert(SEQUENCER_GRACE_PERIOD_NOT_OVER_SELECTOR);
        adapter.getExchangeRate();
    }
}
