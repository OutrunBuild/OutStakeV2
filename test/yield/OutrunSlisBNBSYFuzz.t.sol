// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

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

    /// @dev Mixed-sequence fuzz: randomly interleaves deposit(BNB), deposit(slisBNB),
    ///      and redeem across multiple rounds with varying exchange rates.
    ///      The invariant `totalSupply == slisBNB.balanceOf(address(sy))` must hold
    ///      after every single operation.
    function testFuzz_MixedDepositRedeemInvariant(uint256 seed, uint8 rounds) external {
        rounds = uint8(bound(uint256(rounds), 3, 10));

        for (uint8 i = 0; i < rounds; i++) {
            // Derive action and amount from seed — each round consumes a different
            // portion of the seed via shift so actions are independently random.
            uint256 roundSeed = uint256(keccak256(abi.encode(seed, i)));
            uint8 action = uint8((roundSeed >> 248) % 3);
            // Bound amount so deposits stay within reasonable range.
            // Min 2 ether for native deposits to survive worst-case rate conversion.
            uint256 amount = bound(uint256(roundSeed >> 128), 2 ether, 100 ether);

            // Randomize exchange rate each round to stress the native deposit path.
            uint256 rate = bound(uint256(keccak256(abi.encode(seed, i, "rate"))), 0.5 ether, 1.5 ether);
            stakeManager.setExchangeRateQuote(rate);

            if (action == 0) {
                // --- deposit(BNB) ---
                vm.deal(USER, amount);
                vm.prank(USER);
                sy.deposit{value: amount}(USER, NATIVE, amount, 0);
            } else if (action == 1) {
                // --- deposit(slisBNB) ---
                // Mint slisBNB to USER (simulates holding from prior redeem or external source)
                slisBNB.mint(USER, amount);
                vm.startPrank(USER);
                slisBNB.approve(address(sy), amount);
                sy.deposit(USER, address(slisBNB), amount, 0);
                vm.stopPrank();
            } else {
                // --- redeem(slisBNB) ---
                uint256 syBal = sy.balanceOf(USER);
                if (syBal == 0) continue;
                uint256 redeemAmt = bound(amount, 1, syBal);
                vm.prank(USER);
                sy.redeem(USER, redeemAmt, address(slisBNB), 0, false);
            }

            // Invariant must hold after every single operation.
            assertEq(sy.totalSupply(), slisBNB.balanceOf(address(sy)));
        }
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
