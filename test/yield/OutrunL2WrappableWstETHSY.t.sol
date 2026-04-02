// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {OutrunERC20} from "../../src/assets/base/OutrunERC20.sol";
import {OutrunExchangeOracleAdapter} from "../../src/libraries/oracle/OutrunExchangeOracleAdapter.sol";
import {OutrunL2WrappableWstETHSY} from "../../src/yield/adapters/lido/OutrunL2WrappableWstETHSY.sol";

contract MockERC20Token is OutrunERC20 {
    constructor(string memory name_, string memory symbol_, uint8 decimals_) OutrunERC20(name_, symbol_, decimals_) {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }
}

contract MockL2StETH is OutrunERC20 {
    MockERC20Token internal immutable wstETH;

    constructor(address wstETH_) OutrunERC20("L2 stETH", "stETH", 18) {
        wstETH = MockERC20Token(wstETH_);
    }

    function wrap(uint256 wrappableTokenAmount) external returns (uint256) {
        wstETH.transferFrom(msg.sender, address(this), wrappableTokenAmount);
        _mint(msg.sender, wrappableTokenAmount);
        return wrappableTokenAmount;
    }

    function unwrap(uint256 wrapperTokenAmount) external returns (uint256) {
        _burn(msg.sender, wrapperTokenAmount);
        wstETH.transfer(msg.sender, wrapperTokenAmount);
        return wrapperTokenAmount;
    }

    function getTokensByShares(uint256 sharesAmount) external pure returns (uint256) {
        return sharesAmount;
    }

    function getSharesByTokens(uint256 tokenAmount) external pure returns (uint256) {
        return tokenAmount;
    }
}

contract MockRawTokenRateOracle {
    int256 internal immutable answer;
    uint8 internal immutable rawDecimals;

    constructor(int256 answer_, uint8 rawDecimals_) {
        answer = answer_;
        rawDecimals = rawDecimals_;
    }

    function decimals() external view returns (uint8) {
        return rawDecimals;
    }

    function description() external pure returns (string memory) {
        return "mock token rate";
    }

    function version() external pure returns (uint256) {
        return 1;
    }

    function latestAnswer() external view returns (int256) {
        return answer;
    }

    function latestTimestamp() external view returns (uint256) {
        return block.timestamp;
    }

    function latestRound() external pure returns (uint256) {
        return 1;
    }

    function getAnswer(uint256) external view returns (int256) {
        return answer;
    }

    function getTimestamp(uint256) external view returns (uint256) {
        return block.timestamp;
    }

    function getRoundData(uint80)
        external
        view
        returns (uint80 roundId, int256 answer_, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (1, answer, block.timestamp, block.timestamp, 1);
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer_, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (1, answer, block.timestamp, block.timestamp, 1);
    }
}

contract OutrunL2WrappableWstETHSYTest is Test {
    address internal constant OWNER = address(0xA11CE);
    address internal constant USER = address(0xB0B);
    address internal constant RECEIVER = address(0xCAFE);

    uint256 internal constant AMOUNT = 5 ether;
    uint256 internal constant NORMALIZED_RATE = 15e17;
    uint256 internal constant RAW_RATE = 15e26;

    MockERC20Token internal wstETH;
    MockL2StETH internal stETH;
    MockRawTokenRateOracle internal rawOracle;
    OutrunExchangeOracleAdapter internal oracleAdapter;
    OutrunL2WrappableWstETHSY internal sy;

    function setUp() external {
        wstETH = new MockERC20Token("Wrapped stETH", "wstETH", 18);
        stETH = new MockL2StETH(address(wstETH));
        rawOracle = new MockRawTokenRateOracle(int256(RAW_RATE), 27);
        oracleAdapter = new OutrunExchangeOracleAdapter(address(rawOracle), 18);
        sy = new OutrunL2WrappableWstETHSY(
            OWNER, address(stETH), address(wstETH), address(oracleAdapter), address(stETH), 18
        );

        wstETH.mint(USER, AMOUNT);
    }

    function testRedeemToStETHTransfersWrappedTokenToReceiver() external {
        vm.startPrank(USER);
        wstETH.approve(address(sy), type(uint256).max);
        sy.deposit(USER, address(wstETH), AMOUNT, 0);
        sy.redeem(RECEIVER, AMOUNT, address(stETH), 0, false);
        vm.stopPrank();

        assertEq(stETH.balanceOf(RECEIVER), AMOUNT);
        assertEq(stETH.balanceOf(address(sy)), 0);
    }

    function testRedeemToWrappedTokenTransfersToReceiver() external {
        vm.startPrank(USER);
        wstETH.approve(address(sy), type(uint256).max);
        sy.deposit(USER, address(wstETH), AMOUNT, 0);
        sy.redeem(RECEIVER, AMOUNT, address(wstETH), 0, false);
        vm.stopPrank();

        assertEq(wstETH.balanceOf(RECEIVER), AMOUNT);
        assertEq(wstETH.balanceOf(address(sy)), 0);
    }

    function testExchangeRateUsesNormalizedOracleValue() external {
        assertEq(sy.exchangeRate(), NORMALIZED_RATE);
    }
}
