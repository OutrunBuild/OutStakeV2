// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {IStandardizedYield} from "../../src/yield/interfaces/IStandardizedYield.sol";
import {OutrunSlisBNBSY} from "../../src/yield/adapters/lista/OutrunSlisBNBSY.sol";
import {MockListaSlisBNB, MockListaStakeManager, MockListaStakeManagerZeroDeposit} from "./mocks/ListaSYMocks.sol";

contract OutrunSlisBNBSYFuzzTest is Test {
    address internal constant OWNER = address(0xA11CE);
    address internal constant USER = address(0xB0B);
    address internal constant NATIVE = address(0);

    uint256 internal constant MIN_AMOUNT = 1;
    uint256 internal constant MAX_AMOUNT = 1_000_000 ether;

    MockListaSlisBNB internal slisBNB;
    MockListaStakeManager internal stakeManager;
    OutrunSlisBNBSY internal sy;

    function setUp() external {
        slisBNB = new MockListaSlisBNB();
        stakeManager = new MockListaStakeManager(slisBNB);
        stakeManager.setExchangeRateQuote(0.98 ether);

        sy = new OutrunSlisBNBSY(OWNER, address(slisBNB), address(stakeManager));
    }

    function testFuzz_DepositNativeTracksSlisBnbBalance(uint256 amount) external {
        // Minimum amount must produce at least 1 slisBNB share after rate conversion
        // to avoid StakeManagerDepositZero: amount * 0.98 ether / 1 ether >= 1
        amount = bound(amount, 2 ether, 1e24 ether);
        vm.deal(USER, amount);

        vm.prank(USER);
        sy.deposit{value: amount}(USER, NATIVE, amount, 0);

        assertEq(sy.totalSupply(), slisBNB.balanceOf(address(sy)));
    }

    function testFuzz_DepositSlisBnbTracksSlisBnbBalance(uint256 amount) external {
        amount = bound(amount, MIN_AMOUNT, 1e24 ether);
        slisBNB.mint(USER, amount);

        vm.startPrank(USER);
        slisBNB.approve(address(sy), amount);
        sy.deposit(USER, address(slisBNB), amount, 0);
        vm.stopPrank();

        assertEq(sy.totalSupply(), slisBNB.balanceOf(address(sy)));
    }

    function testFuzz_DepositNativeWithVaryingRateTracksBalance(uint256 amount, uint256 rate) external {
        // Minimum amount must produce >= 1 slisBNB at lowest rate (0.5 ether):
        // amount * 0.5 ether / 1 ether >= 1 => amount >= 2
        amount = bound(amount, 2, 1e24 ether);
        rate = bound(rate, 0.5 ether, 1.5 ether);
        stakeManager.setExchangeRateQuote(rate);

        vm.deal(USER, amount);

        vm.prank(USER);
        sy.deposit{value: amount}(USER, NATIVE, amount, 0);

        assertEq(sy.totalSupply(), slisBNB.balanceOf(address(sy)));
    }

    function testFuzz_RedeemLeavesNoResidualSlisBnb(uint256 depositAmount, uint256 redeemAmount) external {
        depositAmount = bound(depositAmount, MIN_AMOUNT, MAX_AMOUNT);
        slisBNB.mint(USER, depositAmount);

        vm.startPrank(USER);
        slisBNB.approve(address(sy), depositAmount);
        sy.deposit(USER, address(slisBNB), depositAmount, 0);

        uint256 balance = sy.balanceOf(USER);
        redeemAmount = bound(redeemAmount, MIN_AMOUNT, balance);
        sy.redeem(USER, redeemAmount, address(slisBNB), 0, false);
        vm.stopPrank();

        assertEq(slisBNB.balanceOf(address(sy)), sy.totalSupply());
    }

    function testFuzz_DepositNativeZeroOutputLeavesNoHalfState(uint256 amount) external {
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);

        MockListaStakeManagerZeroDeposit zeroSM = new MockListaStakeManagerZeroDeposit(slisBNB);
        OutrunSlisBNBSY zeroSy = new OutrunSlisBNBSY(OWNER, address(slisBNB), address(zeroSM));

        vm.deal(USER, amount);

        vm.prank(USER);
        vm.expectRevert(OutrunSlisBNBSY.StakeManagerDepositZero.selector);
        zeroSy.deposit{value: amount}(USER, NATIVE, amount, 0);

        assertEq(zeroSy.totalSupply(), 0);
        assertEq(zeroSy.balanceOf(USER), 0);
        assertEq(slisBNB.balanceOf(address(zeroSy)), 0);
        assertEq(address(zeroSy).balance, 0);
    }
}
