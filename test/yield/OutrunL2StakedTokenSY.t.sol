// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {OutrunERC20} from "../../src/assets/base/OutrunERC20.sol";
import {IStandardizedYield} from "../../src/yield/interfaces/IStandardizedYield.sol";
import {OutrunL2StakedTokenSY} from "../../src/yield/OutrunL2StakedTokenSY.sol";

contract MockERC20Token is OutrunERC20 {
    constructor() OutrunERC20("Mock Staked Token", "mstTOKEN", 18) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockExchangeRateOracle {
    uint256 public exchangeRateValue;

    constructor(uint256 _exchangeRateValue) {
        exchangeRateValue = _exchangeRateValue;
    }

    function setExchangeRate(uint256 _exchangeRateValue) external {
        exchangeRateValue = _exchangeRateValue;
    }

    function getExchangeRate() external view returns (uint256) {
        return exchangeRateValue;
    }
}

contract OutrunL2StakedTokenSYTest is Test {
    address internal constant OWNER = address(0xA11CE);
    address internal constant USER = address(0xB0B);
    address internal constant UNDERLYING_ASSET = address(0xDEAD);

    uint256 internal constant AMOUNT = 5 ether;
    uint256 internal constant INITIAL_EXCHANGE_RATE = 1.1e18;

    MockERC20Token internal stakedToken;
    MockExchangeRateOracle internal oracle;
    OutrunL2StakedTokenSY internal sy;

    function setUp() external {
        stakedToken = new MockERC20Token();
        oracle = new MockExchangeRateOracle(INITIAL_EXCHANGE_RATE);
        sy = new OutrunL2StakedTokenSY(
            "SY L2 Staked Token", "SY L2 stTOKEN", OWNER, address(stakedToken), address(oracle), UNDERLYING_ASSET, 18
        );

        stakedToken.mint(USER, AMOUNT * 10);
    }

    // ============================================
    // Deposit paths
    // ============================================

    function testDepositYieldBearingTokenPassthrough() external {
        uint256 syBalanceBefore = sy.balanceOf(USER);
        uint256 tokenBalanceBefore = stakedToken.balanceOf(USER);

        vm.prank(USER);
        stakedToken.approve(address(sy), AMOUNT);

        vm.prank(USER);
        uint256 sharesOut = sy.deposit(USER, address(stakedToken), AMOUNT, 0);

        // Verify 1:1 passthrough
        assertEq(sharesOut, AMOUNT, "sharesOut should equal AMOUNT (1:1 passthrough)");
        assertEq(sy.balanceOf(USER), syBalanceBefore + AMOUNT, "SY balance should increase");
        assertEq(stakedToken.balanceOf(USER), tokenBalanceBefore - AMOUNT, "stakedToken should be transferred out");
    }

    // ============================================
    // Redeem paths
    // ============================================

    function testRedeemToYieldBearingToken() external {
        // First deposit to get SY shares
        vm.prank(USER);
        stakedToken.approve(address(sy), AMOUNT);
        vm.prank(USER);
        uint256 sharesOut = sy.deposit(USER, address(stakedToken), AMOUNT, 0);

        uint256 tokenBalanceBefore = stakedToken.balanceOf(USER);

        vm.prank(USER);
        uint256 amountOut = sy.redeem(USER, sharesOut, address(stakedToken), 0, false);

        // Verify token transferred out
        assertEq(amountOut, sharesOut, "amountOut should equal shares redeemed");
        assertEq(stakedToken.balanceOf(USER), tokenBalanceBefore + sharesOut, "stakedToken should be received");
        assertEq(sy.balanceOf(USER), 0, "SY shares should be burned");
    }

    // ============================================
    // Exchange rate
    // ============================================

    function testExchangeRateReadsOracle() external {
        uint256 rateBefore = sy.exchangeRate();
        assertEq(rateBefore, INITIAL_EXCHANGE_RATE, "exchangeRate should return oracle value");

        // Update oracle rate
        oracle.setExchangeRate(1.2e18);
        uint256 rateAfter = sy.exchangeRate();
        assertEq(rateAfter, 1.2e18, "exchangeRate should reflect updated oracle value");
    }

    function testDepositSlippageReverts() external {
        vm.prank(USER);
        stakedToken.approve(address(sy), AMOUNT);

        uint256 slippageMinShares = AMOUNT + 1;
        vm.prank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(IStandardizedYield.SYInsufficientSharesOut.selector, AMOUNT, slippageMinShares)
        );
        sy.deposit(USER, address(stakedToken), AMOUNT, slippageMinShares);
    }

    function testExchangeRateReflectsOracleRateChange() external {
        uint256 rateBefore = sy.exchangeRate();
        oracle.setExchangeRate(1.2e18);
        uint256 rateAfter = sy.exchangeRate();
        assertTrue(rateAfter > rateBefore, "exchange rate should increase with oracle rate");
    }

    function testDepositZeroReverts() external {
        vm.prank(USER);
        stakedToken.approve(address(sy), 1 ether);
        vm.expectRevert(IStandardizedYield.SYZeroDeposit.selector);
        sy.deposit(USER, address(stakedToken), 0, 0);
    }

    function testRedeemZeroReverts() external {
        vm.prank(USER);
        vm.expectRevert(IStandardizedYield.SYZeroRedeem.selector);
        sy.redeem(USER, 0, address(stakedToken), 0, false);
    }
}
