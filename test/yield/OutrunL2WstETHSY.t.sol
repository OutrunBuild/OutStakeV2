// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {OutrunERC20} from "../../src/assets/base/OutrunERC20.sol";
import {OutrunL2WstETHSY} from "../../src/yield/adapters/lido/OutrunL2WstETHSY.sol";

contract MockWstETH is OutrunERC20 {
    constructor() OutrunERC20("Wrapped liquid staked Ether 2.0", "wstETH", 18) {}

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

contract OutrunL2WstETHSYTest is Test {
    address internal constant OWNER = address(0xA11CE);
    address internal constant USER = address(0xB0B);
    address internal constant UNDERLYING_ASSET = address(0xDEAD);

    uint256 internal constant AMOUNT = 5 ether;
    uint256 internal constant INITIAL_EXCHANGE_RATE = 1.1e18;

    MockWstETH internal wstETH;
    MockExchangeRateOracle internal oracle;
    OutrunL2WstETHSY internal sy;

    function setUp() external {
        wstETH = new MockWstETH();
        oracle = new MockExchangeRateOracle(INITIAL_EXCHANGE_RATE);
        sy = new OutrunL2WstETHSY(OWNER, address(wstETH), address(oracle), UNDERLYING_ASSET, 18);

        wstETH.mint(USER, AMOUNT * 10);
    }

    // ============================================
    // Deposit paths
    // ============================================

    function testDepositYieldBearingTokenPassthrough() external {
        uint256 syBalanceBefore = sy.balanceOf(USER);
        uint256 wstETHBalanceBefore = wstETH.balanceOf(USER);

        vm.prank(USER);
        wstETH.approve(address(sy), AMOUNT);

        vm.prank(USER);
        uint256 sharesOut = sy.deposit(USER, address(wstETH), AMOUNT, 0);

        // Verify 1:1 passthrough
        assertEq(sharesOut, AMOUNT, "sharesOut should equal AMOUNT (1:1 passthrough)");
        assertEq(sy.balanceOf(USER), syBalanceBefore + AMOUNT, "SY balance should increase");
        assertEq(wstETH.balanceOf(USER), wstETHBalanceBefore - AMOUNT, "wstETH should be transferred out");
    }

    // ============================================
    // Redeem paths
    // ============================================

    function testRedeemToYieldBearingToken() external {
        // First deposit to get SY shares
        vm.prank(USER);
        wstETH.approve(address(sy), AMOUNT);
        vm.prank(USER);
        uint256 sharesOut = sy.deposit(USER, address(wstETH), AMOUNT, 0);

        uint256 wstETHBalanceBefore = wstETH.balanceOf(USER);

        vm.prank(USER);
        uint256 amountOut = sy.redeem(USER, sharesOut, address(wstETH), 0, false);

        // Verify token transferred out
        assertEq(amountOut, sharesOut, "amountOut should equal shares redeemed");
        assertEq(wstETH.balanceOf(USER), wstETHBalanceBefore + sharesOut, "wstETH should be received");
        assertEq(sy.balanceOf(USER), 0, "SY shares should be burned");
    }

    // ============================================
    // Exchange rate
    // ============================================

    function testExchangeRateReadsOracle() external {
        uint256 rate = sy.exchangeRate();
        assertEq(rate, INITIAL_EXCHANGE_RATE, "exchangeRate should return oracle value");

        // Update oracle rate
        oracle.setExchangeRate(1.2e18);
        rate = sy.exchangeRate();
        assertEq(rate, 1.2e18, "exchangeRate should reflect updated oracle value");
    }
}
