// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {MockAUSDCOracle} from "./MockAUSDCOracle.sol";
import {MockSUSDSOracle} from "./MockSUSDSOracle.sol";
import {OutrunExchangeOracleAdapter} from "../../src/libraries/oracle/OutrunExchangeOracleAdapter.sol";

contract MockAggregator {
    int256 internal latestOracleAnswer;

    function setLatestAnswer(int256 answer) external {
        latestOracleAnswer = answer;
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
        return block.timestamp;
    }

    function latestRound() external pure returns (uint256) {
        return 1;
    }

    function getAnswer(uint256) external view returns (int256) {
        return latestOracleAnswer;
    }

    function getTimestamp(uint256) external view returns (uint256) {
        return block.timestamp;
    }

    function getRoundData(uint80)
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (1, latestOracleAnswer, block.timestamp, block.timestamp, 1);
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (1, latestOracleAnswer, block.timestamp, block.timestamp, 1);
    }
}

contract MockOracleWarningsTest is Test {
    bytes4 internal constant INVALID_ORACLE_ANSWER_SELECTOR = bytes4(keccak256("InvalidOracleAnswer()"));

    address internal owner = address(0xA11CE);

    MockSUSDSOracle internal susdsOracle;
    MockAUSDCOracle internal ausdcOracle;
    MockAggregator internal aggregator;
    OutrunExchangeOracleAdapter internal adapter;

    function setUp() external {
        susdsOracle = new MockSUSDSOracle(owner);
        ausdcOracle = new MockAUSDCOracle(owner);
        aggregator = new MockAggregator();
        adapter = new OutrunExchangeOracleAdapter(address(aggregator), 18);
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
}
