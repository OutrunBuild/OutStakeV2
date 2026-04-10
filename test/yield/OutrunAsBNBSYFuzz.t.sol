// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {OutrunAsBNBSY} from "../../src/yield/adapters/aster/OutrunAsBNBSY.sol";
import {
    MockAsBNB,
    MockAsBnbMinter,
    MockListaBNBStakeManager,
    MockSlisBNB,
    MockYieldProxy
} from "./mocks/AsterSYMocks.sol";

contract OutrunAsBNBSYFuzzTest is Test {
    address internal constant OWNER = address(0xA11CE);
    address internal constant USER = address(0xB0B);
    address internal constant NATIVE = address(0);

    uint256 internal constant MIN_AMOUNT = 1;
    uint256 internal constant MAX_AMOUNT = 1_000_000 ether;
    uint256 internal constant MIN_RATIO = 0.1 ether;
    uint256 internal constant MAX_RATIO = 3 ether;

    MockAsBNB internal asBNB;
    MockSlisBNB internal slisBNB;
    MockListaBNBStakeManager internal stakeManager;
    MockYieldProxy internal yieldProxy;
    MockAsBnbMinter internal minter;
    OutrunAsBNBSY internal sy;

    function setUp() external {
        asBNB = new MockAsBNB();
        slisBNB = new MockSlisBNB();
        stakeManager = new MockListaBNBStakeManager();
        yieldProxy = new MockYieldProxy(address(stakeManager));
        minter = new MockAsBnbMinter(address(asBNB), address(slisBNB), address(yieldProxy));
        sy = new OutrunAsBNBSY(OWNER, address(asBNB), address(slisBNB), address(minter));
    }

    function testFuzz_DepositAsBnbTracksUnderlyingBalance(uint256 amount) external {
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);
        asBNB.mint(USER, amount);

        vm.startPrank(USER);
        asBNB.approve(address(sy), amount);
        sy.deposit(USER, address(asBNB), amount, 0);
        vm.stopPrank();

        assertEq(sy.totalSupply(), asBNB.balanceOf(address(sy)));
    }

    function testFuzz_DepositSlisBnbLeavesNoResidualSlisBnb(uint256 amount, uint256 convertToAsBnbRatio) external {
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);
        convertToAsBnbRatio = bound(convertToAsBnbRatio, MIN_RATIO, MAX_RATIO);
        vm.assume((amount * convertToAsBnbRatio) / 1 ether > 0);
        minter.setConvertToAsBnbQuote(convertToAsBnbRatio);

        slisBNB.mint(USER, amount);

        vm.startPrank(USER);
        slisBNB.approve(address(sy), amount);
        sy.deposit(USER, address(slisBNB), amount, 0);
        vm.stopPrank();

        assertEq(slisBNB.balanceOf(address(sy)), 0);
        assertEq(sy.totalSupply(), asBNB.balanceOf(address(sy)));
    }

    function testFuzz_DepositSlisBnbQueueLeavesNoHalfState(uint256 amount) external {
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);
        minter.setQueueMode(true);
        slisBNB.mint(USER, amount);

        vm.startPrank(USER);
        slisBNB.approve(address(sy), amount);
        vm.expectRevert(OutrunAsBNBSY.AsBnbMintQueued.selector);
        sy.deposit(USER, address(slisBNB), amount, 0);
        vm.stopPrank();

        assertEq(sy.totalSupply(), 0);
        assertEq(sy.balanceOf(USER), 0);
        assertEq(asBNB.balanceOf(address(sy)), 0);
        assertEq(slisBNB.balanceOf(address(sy)), 0);
    }

    function testFuzz_DepositNativeQueueLeavesNoHalfState(uint256 amount) external {
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);
        minter.setQueueMode(true);
        vm.deal(USER, amount);

        vm.prank(USER);
        vm.expectRevert(OutrunAsBNBSY.AsBnbMintQueued.selector);
        sy.deposit{value: amount}(USER, NATIVE, amount, 0);

        assertEq(sy.totalSupply(), 0);
        assertEq(sy.balanceOf(USER), 0);
        assertEq(asBNB.balanceOf(address(sy)), 0);
        assertEq(address(sy).balance, 0);
    }
}
