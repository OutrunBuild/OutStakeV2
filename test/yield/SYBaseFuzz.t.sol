// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {MockSYBaseToken, MockSYBase} from "./SYBaseDeposit.t.sol";

/**
 * @title SYBaseFuzzTest
 * @dev Comprehensive fuzz tests for SYBase contract covering:
 *      - Deposit/redeem roundtrip integrity
 *      - Slippage protection edge cases
 *      - Preview vs actual consistency
 *      - Burn from internal balance
 *      - Native token handling
 *      - Multiple deposits accumulation
 *      - Partial redemptions
 *      - ERC20 input with msg.value revert
 */
contract SYBaseFuzzTest is Test {
    // Error selectors
    bytes4 internal constant NATIVE_AMOUNT_MISMATCH_SELECTOR = bytes4(keccak256("NativeAmountMismatch()"));
    bytes4 internal constant SY_INSUFFICIENT_SHARES_OUT_SELECTOR =
        bytes4(keccak256("SYInsufficientSharesOut(uint256,uint256)"));
    bytes4 internal constant SY_INSUFFICIENT_TOKEN_OUT_SELECTOR =
        bytes4(keccak256("SYInsufficientTokenOut(uint256,uint256)"));

    // Constants
    address internal constant NATIVE = address(0);
    uint256 internal constant MIN_AMOUNT = 1;
    uint256 internal constant MAX_AMOUNT = 10000e18;

    // Test contracts
    MockSYBaseToken internal underlying;
    MockSYBase internal sy;

    // Test addresses
    address internal owner = address(0xA11CE);
    address internal user = address(0xBEEF);
    address internal receiver = address(0xCAFE);

    function setUp() external {
        underlying = new MockSYBaseToken();
        sy = new MockSYBase(owner, address(underlying));

        // Setup initial balances and approvals
        underlying.mint(user, MAX_AMOUNT * 10);
        vm.deal(user, MAX_AMOUNT * 10);

        vm.prank(user);
        underlying.approve(address(sy), type(uint256).max);
    }

    // =============================================================
    //                  1. DEPOSIT/REDEEM ROUNDTRIP
    // =============================================================

    /**
     * @dev Test deposit and full redeem roundtrip with ERC20 token
     *      Ensures no token loss occurs during the roundtrip
     */
    function testFuzz_DepositRedeemRoundtrip(uint256 amount) public {
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);

        uint256 initialBalance = underlying.balanceOf(user);

        // Deposit
        vm.startPrank(user);
        uint256 sharesOut = sy.deposit(user, address(underlying), amount, 0);
        vm.stopPrank();

        assertEq(sharesOut, amount, "Shares out should equal deposit amount (1:1)");
        assertEq(sy.balanceOf(user), amount, "User should have correct share balance");
        assertEq(underlying.balanceOf(user), initialBalance - amount, "User tokens should be transferred");

        // Redeem full amount
        vm.prank(user);
        uint256 tokensOut = sy.redeem(user, amount, address(underlying), 0, false);

        assertEq(tokensOut, amount, "Tokens out should equal redeem amount (1:1)");
        assertEq(sy.balanceOf(user), 0, "User should have no shares left");
        assertEq(underlying.balanceOf(user), initialBalance, "User should have initial balance back");
    }

    // =============================================================
    //                  2. DEPOSIT WITH SLIPPAGE PROTECTION
    // =============================================================

    /**
     * @dev Test deposit reverts when slippage exceeds minSharesOut
     *      - If minSharesOut > amount: should revert
     *      - If minSharesOut <= amount: should succeed
     */
    function testFuzz_DepositRevertsWhenSlippageExceedsMinShares(uint256 amount, uint256 minSharesOut) public {
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);
        // minSharesOut can be any value to test both success and revert cases

        vm.prank(user);
        if (minSharesOut > amount) {
            // Should revert because actual shares (amount) < minSharesOut
            vm.expectRevert(abi.encodeWithSelector(SY_INSUFFICIENT_SHARES_OUT_SELECTOR, amount, minSharesOut));
            sy.deposit(user, address(underlying), amount, minSharesOut);
        } else {
            // Should succeed because actual shares (amount) >= minSharesOut
            uint256 sharesOut = sy.deposit(user, address(underlying), amount, minSharesOut);
            assertEq(sharesOut, amount);
        }
    }

    /**
     * @dev Test deposit succeeds at boundary when minSharesOut equals amount
     */
    function testFuzz_DepositSucceedsAtExactMinShares(uint256 amount) public {
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);

        vm.prank(user);
        uint256 sharesOut = sy.deposit(user, address(underlying), amount, amount);

        assertEq(sharesOut, amount, "Shares out should equal amount at boundary");
    }

    /**
     * @dev Test deposit succeeds when minSharesOut is slightly below amount
     */
    function testFuzz_DepositSucceedsWithSlippageTolerance(uint256 amount, uint256 slippageBps) public {
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);
        slippageBps = bound(slippageBps, 0, 10000); // 0% to 100% slippage tolerance

        uint256 minSharesOut = (amount * (10000 - slippageBps)) / 10000;

        vm.prank(user);
        uint256 sharesOut = sy.deposit(user, address(underlying), amount, minSharesOut);

        assertEq(sharesOut, amount);
    }

    // =============================================================
    //                  3. REDEEM WITH SLIPPAGE PROTECTION
    // =============================================================

    /**
     * @dev Test redeem reverts when slippage exceeds minTokenOut
     */
    function testFuzz_RedeemRevertsWhenSlippageExceedsMinTokenOut(uint256 amount, uint256 minTokenOut) public {
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);

        // First deposit to get shares
        vm.prank(user);
        sy.deposit(user, address(underlying), amount, 0);

        vm.prank(user);
        if (minTokenOut > amount) {
            vm.expectRevert(abi.encodeWithSelector(SY_INSUFFICIENT_TOKEN_OUT_SELECTOR, amount, minTokenOut));
            sy.redeem(user, amount, address(underlying), minTokenOut, false);
        } else {
            uint256 tokensOut = sy.redeem(user, amount, address(underlying), minTokenOut, false);
            assertEq(tokensOut, amount);
        }
    }

    /**
     * @dev Test redeem succeeds at boundary when minTokenOut equals amount
     */
    function testFuzz_RedeemSucceedsAtExactMinTokenOut(uint256 amount) public {
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);

        vm.startPrank(user);
        sy.deposit(user, address(underlying), amount, 0);
        uint256 tokensOut = sy.redeem(user, amount, address(underlying), amount, false);
        vm.stopPrank();

        assertEq(tokensOut, amount, "Tokens out should equal amount at boundary");
    }

    // =============================================================
    //                  4. BURN FROM INTERNAL BALANCE
    // =============================================================

    /**
     * @dev Test redeem with burnFromInternalBalance option
     *      Shares should be burned from SY contract's balance, not user's
     */
    function testFuzz_RedeemBurnFromInternalBalance(uint256 depositAmount, uint256 redeemAmount) public {
        depositAmount = bound(depositAmount, MIN_AMOUNT, MAX_AMOUNT);
        redeemAmount = bound(redeemAmount, MIN_AMOUNT, depositAmount);

        // User deposits and gets shares
        vm.prank(user);
        sy.deposit(user, address(underlying), depositAmount, 0);

        uint256 userSharesBefore = sy.balanceOf(user);
        uint256 syContractSharesBefore = sy.balanceOf(address(sy));
        assertEq(userSharesBefore, depositAmount);
        assertEq(syContractSharesBefore, 0);

        // User transfers shares to SY contract
        vm.prank(user);
        sy.transfer(address(sy), redeemAmount);

        uint256 userSharesAfterTransfer = sy.balanceOf(user);
        uint256 syContractSharesAfterTransfer = sy.balanceOf(address(sy));
        assertEq(userSharesAfterTransfer, depositAmount - redeemAmount);
        assertEq(syContractSharesAfterTransfer, redeemAmount);

        // Redeem with burnFromInternalBalance = true
        vm.prank(user);
        uint256 amountTokenOut = sy.redeem(user, redeemAmount, address(underlying), 0, true);

        assertEq(amountTokenOut, redeemAmount, "Token out should equal redeem amount");
        // User's share balance should remain unchanged from after transfer
        assertEq(sy.balanceOf(user), depositAmount - redeemAmount, "User shares unchanged");
        // SY contract's share balance should be reduced by redeemAmount
        assertEq(sy.balanceOf(address(sy)), 0, "SY shares burned from internal balance");
    }

    /**
     * @dev Test burnFromInternalBalance with full amount
     */
    function testFuzz_RedeemBurnFromInternalBalanceFullAmount(uint256 depositAmount) public {
        depositAmount = bound(depositAmount, MIN_AMOUNT, MAX_AMOUNT);

        vm.startPrank(user);
        sy.deposit(user, address(underlying), depositAmount, 0);

        // Transfer all shares to SY contract
        sy.transfer(address(sy), depositAmount);

        // Redeem all with burnFromInternalBalance
        uint256 tokensOut = sy.redeem(user, depositAmount, address(underlying), 0, true);
        vm.stopPrank();

        assertEq(tokensOut, depositAmount);
        assertEq(sy.balanceOf(user), 0);
        assertEq(sy.balanceOf(address(sy)), 0);
    }

    // =============================================================
    //                  5. PREVIEW DEPOSIT MATCHES ACTUAL
    // =============================================================

    /**
     * @dev Test previewDeposit returns same value as actual deposit
     */
    function testFuzz_PreviewDepositMatchesActual(uint256 amount) public {
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);

        uint256 previewShares = sy.previewDeposit(address(underlying), amount);

        vm.prank(user);
        uint256 actualShares = sy.deposit(user, address(underlying), amount, 0);

        assertEq(previewShares, actualShares, "Preview should match actual deposit");
        assertEq(previewShares, amount, "Preview should equal amount (1:1 mock)");
    }

    /**
     * @dev Test previewDeposit with native token
     */
    function testFuzz_PreviewDepositMatchesActualNative(uint256 amount) public {
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);

        uint256 previewShares = sy.previewDeposit(NATIVE, amount);

        vm.prank(user);
        uint256 actualShares = sy.deposit{value: amount}(user, NATIVE, amount, 0);

        assertEq(previewShares, actualShares, "Preview should match actual native deposit");
    }

    // =============================================================
    //                  6. PREVIEW REDEEM MATCHES ACTUAL
    // =============================================================

    /**
     * @dev Test previewRedeem returns same value as actual redeem
     */
    function testFuzz_PreviewRedeemMatchesActual(uint256 amount) public {
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);

        // First deposit
        vm.prank(user);
        sy.deposit(user, address(underlying), amount, 0);

        uint256 previewTokens = sy.previewRedeem(address(underlying), amount);

        vm.prank(user);
        uint256 actualTokens = sy.redeem(user, amount, address(underlying), 0, false);

        assertEq(previewTokens, actualTokens, "Preview should match actual redeem");
        assertEq(previewTokens, amount, "Preview should equal amount (1:1 mock)");
    }

    /**
     * @dev Test previewRedeem with native token output
     */
    function testFuzz_PreviewRedeemMatchesActualNative(uint256 amount) public {
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);

        // First deposit native
        vm.prank(user);
        sy.deposit{value: amount}(user, NATIVE, amount, 0);

        uint256 previewTokens = sy.previewRedeem(NATIVE, amount);

        vm.prank(user);
        uint256 actualTokens = sy.redeem(user, amount, NATIVE, 0, false);

        assertEq(previewTokens, actualTokens, "Preview should match actual native redeem");
    }

    // =============================================================
    //                  7. NATIVE INPUT PATH
    // =============================================================

    /**
     * @dev Test deposit with native ETH and redeem to native
     */
    function testFuzz_DepositNativeAndRedeem(uint256 amount) public {
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);

        uint256 initialNativeBalance = user.balance;

        // Deposit native
        vm.prank(user);
        uint256 sharesOut = sy.deposit{value: amount}(user, NATIVE, amount, 0);

        assertEq(sharesOut, amount, "Shares should equal native deposit");
        assertEq(sy.balanceOf(user), amount, "User should have shares");
        assertEq(user.balance, initialNativeBalance - amount, "User native balance reduced");
        assertEq(address(sy).balance, amount, "SY contract received native");

        // Redeem to native
        vm.prank(user);
        uint256 tokensOut = sy.redeem(user, amount, NATIVE, 0, false);

        assertEq(tokensOut, amount, "Native tokens out should equal shares");
        assertEq(sy.balanceOf(user), 0, "User should have no shares");
        assertEq(user.balance, initialNativeBalance, "User native balance restored");
        assertEq(address(sy).balance, 0, "SY contract native balance zero");
    }

    /**
     * @dev Test deposit native, redeem to ERC20 (cross-asset)
     *      NOTE: The mock SY contract must hold underlying tokens to redeem to ERC20.
     *      This test verifies the happy path by funding the SY contract with underlying tokens.
     */
    function testFuzz_DepositNativeRedeemERC20(uint256 amount) public {
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);

        // Fund the SY contract with underlying tokens so it can redeem to ERC20
        underlying.mint(address(sy), amount);

        // Deposit native
        vm.prank(user);
        sy.deposit{value: amount}(user, NATIVE, amount, 0);

        uint256 initialUnderlyingBalance = underlying.balanceOf(user);

        // Redeem to ERC20
        vm.prank(user);
        uint256 tokensOut = sy.redeem(user, amount, address(underlying), 0, false);

        assertEq(tokensOut, amount);
        assertEq(underlying.balanceOf(user), initialUnderlyingBalance + amount);
    }

    /**
     * @dev Test deposit ERC20, redeem to native (cross-asset)
     *      NOTE: The mock SY contract must hold native ETH to redeem to native.
     *      This test verifies the happy path by funding the SY contract with native ETH.
     */
    function testFuzz_DepositERC20RedeemNative(uint256 amount) public {
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);

        // Deposit ERC20
        vm.prank(user);
        sy.deposit(user, address(underlying), amount, 0);

        // Fund the SY contract with native ETH so it can redeem to native
        vm.deal(address(sy), amount);

        uint256 initialNativeBalance = user.balance;

        // Redeem to native
        vm.prank(user);
        uint256 tokensOut = sy.redeem(user, amount, NATIVE, 0, false);

        assertEq(tokensOut, amount);
        assertEq(user.balance, initialNativeBalance + amount);
    }

    // =============================================================
    //                  8. MULTIPLE DEPOSITS ACCUMULATE
    // =============================================================

    /**
     * @dev Test multiple deposits accumulate correctly
     */
    function testFuzz_MultipleDepositsAccumulate(uint256[4] memory amounts) public {
        uint256 totalDeposited;

        for (uint256 i = 0; i < 4; i++) {
            amounts[i] = bound(amounts[i], MIN_AMOUNT, MAX_AMOUNT / 4); // Limit to prevent overflow
            totalDeposited += amounts[i];
        }

        // Ensure we have enough balance
        vm.assume(totalDeposited <= MAX_AMOUNT);

        uint256 expectedShares;

        for (uint256 i = 0; i < 4; i++) {
            vm.prank(user);
            uint256 sharesOut = sy.deposit(user, address(underlying), amounts[i], 0);
            expectedShares += amounts[i];

            assertEq(sharesOut, amounts[i], "Each deposit should return correct shares");
            assertEq(sy.balanceOf(user), expectedShares, "Total shares should accumulate");
        }

        assertEq(sy.balanceOf(user), totalDeposited, "Final shares should equal total deposited");
    }

    /**
     * @dev Test alternating deposits with native and ERC20
     */
    function testFuzz_MultipleDepositsMixedTokens(uint256 erc20Amount, uint256 nativeAmount) public {
        erc20Amount = bound(erc20Amount, MIN_AMOUNT, MAX_AMOUNT / 2);
        nativeAmount = bound(nativeAmount, MIN_AMOUNT, MAX_AMOUNT / 2);

        // Deposit ERC20
        vm.prank(user);
        sy.deposit(user, address(underlying), erc20Amount, 0);

        // Deposit native
        vm.prank(user);
        sy.deposit{value: nativeAmount}(user, NATIVE, nativeAmount, 0);

        assertEq(sy.balanceOf(user), erc20Amount + nativeAmount, "Total shares should be sum of deposits");
    }

    // =============================================================
    //                  9. PARTIAL REDEMPTIONS
    // =============================================================

    /**
     * @dev Test partial redemptions maintain correct remaining balance
     *      Ensures redeemAmount < depositAmount to leave remaining shares
     */
    function testFuzz_PartialRedemptions(uint256 depositAmount, uint256 redeemAmount) public {
        depositAmount = bound(depositAmount, MIN_AMOUNT * 2, MAX_AMOUNT);
        // Ensure redeemAmount is strictly less than depositAmount to leave remaining shares
        redeemAmount = bound(redeemAmount, MIN_AMOUNT, depositAmount - 1);

        uint256 initialBalance = underlying.balanceOf(user);

        // Deposit
        vm.prank(user);
        sy.deposit(user, address(underlying), depositAmount, 0);

        // Partial redeem
        vm.prank(user);
        uint256 tokensOut = sy.redeem(user, redeemAmount, address(underlying), 0, false);

        assertEq(tokensOut, redeemAmount, "Tokens out should equal redeem amount");
        assertEq(sy.balanceOf(user), depositAmount - redeemAmount, "Remaining shares correct");
        assertEq(
            underlying.balanceOf(user),
            initialBalance - depositAmount + redeemAmount,
            "Balance correct after partial redeem"
        );

        // Redeem remaining
        vm.prank(user);
        uint256 remainingTokensOut = sy.redeem(user, depositAmount - redeemAmount, address(underlying), 0, false);

        assertEq(remainingTokensOut, depositAmount - redeemAmount, "Remaining tokens out correct");
        assertEq(sy.balanceOf(user), 0, "No shares remaining");
        assertEq(underlying.balanceOf(user), initialBalance, "Full balance restored");
    }

    /**
     * @dev Test multiple partial redemptions
     *      Ensures total redemption doesn't exceed 100% and each partial redeem is valid
     */
    function testFuzz_MultiplePartialRedemptions(uint256 depositAmount, uint256[3] memory redeemFractions) public {
        depositAmount = bound(depositAmount, MIN_AMOUNT * 4, MAX_AMOUNT);

        uint256 totalRedeemFraction;
        for (uint256 i = 0; i < 3; i++) {
            redeemFractions[i] = bound(redeemFractions[i], 0, 3000); // 0% to 30% per redeem (max 90% total)
            totalRedeemFraction += redeemFractions[i];
        }

        // Ensure total doesn't exceed 90% to leave some remaining shares
        vm.assume(totalRedeemFraction <= 9000);

        // Deposit
        vm.prank(user);
        sy.deposit(user, address(underlying), depositAmount, 0);

        uint256 remainingShares = depositAmount;
        uint256 expectedTotalRedeemed;

        for (uint256 i = 0; i < 3; i++) {
            uint256 redeemAmount = (depositAmount * redeemFractions[i]) / 10000;
            if (redeemAmount == 0) continue;

            expectedTotalRedeemed += redeemAmount;

            vm.prank(user);
            uint256 tokensOut = sy.redeem(user, redeemAmount, address(underlying), 0, false);

            remainingShares -= redeemAmount;

            assertEq(tokensOut, redeemAmount, "Tokens out should equal redeem amount");
            assertEq(sy.balanceOf(user), remainingShares, "Remaining shares after partial redeem");
        }

        // Verify total redeemed equals sum of individual redeem amounts
        // This avoids rounding issues from recalculating expected total
        assertEq(remainingShares, depositAmount - expectedTotalRedeemed, "Remaining shares correct");
    }

    // =============================================================
    //                  10. ERC20 INPUT WITH MSG.VALUE REVERTS
    // =============================================================

    /**
     * @dev Test ERC20 input with msg.value always reverts
     */
    function testFuzz_ERC20InputRevertsWithMsgValue(uint256 amount, uint256 msgValue) public {
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);
        msgValue = bound(msgValue, 1, MAX_AMOUNT); // Must be > 0 to trigger revert

        vm.prank(user);
        vm.expectRevert(NATIVE_AMOUNT_MISMATCH_SELECTOR);
        sy.deposit{value: msgValue}(user, address(underlying), amount, 0);
    }

    /**
     * @dev Test native input with mismatched msg.value reverts
     */
    function testFuzz_NativeInputRevertsOnValueMismatch(uint256 amount, uint256 msgValue) public {
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);
        msgValue = bound(msgValue, MIN_AMOUNT, MAX_AMOUNT);

        vm.assume(amount != msgValue);

        vm.prank(user);
        vm.expectRevert(NATIVE_AMOUNT_MISMATCH_SELECTOR);
        sy.deposit{value: msgValue}(user, NATIVE, amount, 0);
    }

    /**
     * @dev Test native input succeeds when msg.value matches amount
     */
    function testFuzz_NativeInputSucceedsOnValueMatch(uint256 amount) public {
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);

        vm.prank(user);
        uint256 sharesOut = sy.deposit{value: amount}(user, NATIVE, amount, 0);

        assertEq(sharesOut, amount);
    }

    // =============================================================
    //                  ADDITIONAL FUZZ TESTS
    // =============================================================

    /**
     * @dev Test receiver can be different from msg.sender
     */
    function testFuzz_DepositToDifferentReceiver(uint256 amount) public {
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);

        vm.prank(user);
        uint256 sharesOut = sy.deposit(receiver, address(underlying), amount, 0);

        assertEq(sharesOut, amount);
        assertEq(sy.balanceOf(user), 0, "User should have no shares");
        assertEq(sy.balanceOf(receiver), amount, "Receiver should have shares");
    }

    /**
     * @dev Test redeem to different receiver
     */
    function testFuzz_RedeemToDifferentReceiver(uint256 amount) public {
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);

        vm.prank(user);
        sy.deposit(user, address(underlying), amount, 0);

        uint256 receiverInitialBalance = underlying.balanceOf(receiver);

        vm.prank(user);
        uint256 tokensOut = sy.redeem(receiver, amount, address(underlying), 0, false);

        assertEq(tokensOut, amount);
        assertEq(underlying.balanceOf(receiver), receiverInitialBalance + amount, "Receiver got tokens");
        assertEq(underlying.balanceOf(user), MAX_AMOUNT * 10 - amount, "User still missing deposited tokens");
    }

    /**
     * @dev Test deposit with zero minSharesOut (no slippage protection)
     */
    function testFuzz_DepositWithZeroMinShares(uint256 amount) public {
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);

        vm.prank(user);
        uint256 sharesOut = sy.deposit(user, address(underlying), amount, 0);

        assertEq(sharesOut, amount);
    }

    /**
     * @dev Test redeem with zero minTokenOut (no slippage protection)
     */
    function testFuzz_RedeemWithZeroMinTokenOut(uint256 amount) public {
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);

        vm.startPrank(user);
        sy.deposit(user, address(underlying), amount, 0);
        uint256 tokensOut = sy.redeem(user, amount, address(underlying), 0, false);
        vm.stopPrank();

        assertEq(tokensOut, amount);
    }

    /**
     * @dev Test exchange rate remains constant (1:1 for mock)
     */
    function testFuzz_ExchangeRateConsistent(uint256 amount) public {
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);

        uint256 rateBefore = sy.exchangeRate();

        vm.prank(user);
        sy.deposit(user, address(underlying), amount, 0);

        uint256 rateAfter = sy.exchangeRate();

        assertEq(rateBefore, rateAfter, "Exchange rate should remain constant");
        assertEq(rateBefore, 1e18, "Exchange rate should be 1:1");
    }

    /**
     * @dev Test total supply increases with deposits
     */
    function testFuzz_TotalSupplyWithDeposits(uint256[3] memory amounts) public {
        uint256 expectedTotalSupply;

        for (uint256 i = 0; i < 3; i++) {
            amounts[i] = bound(amounts[i], MIN_AMOUNT, MAX_AMOUNT / 3);
            expectedTotalSupply += amounts[i];
        }

        for (uint256 i = 0; i < 3; i++) {
            vm.prank(user);
            sy.deposit(user, address(underlying), amounts[i], 0);
        }

        assertEq(sy.totalSupply(), expectedTotalSupply, "Total supply should equal total deposited");
    }

    /**
     * @dev Test total supply decreases with redemptions
     */
    function testFuzz_TotalSupplyWithRedemptions(uint256 depositAmount, uint256 redeemAmount) public {
        depositAmount = bound(depositAmount, MIN_AMOUNT, MAX_AMOUNT);
        redeemAmount = bound(redeemAmount, MIN_AMOUNT, depositAmount);

        vm.prank(user);
        sy.deposit(user, address(underlying), depositAmount, 0);

        assertEq(sy.totalSupply(), depositAmount);

        vm.prank(user);
        sy.redeem(user, redeemAmount, address(underlying), 0, false);

        assertEq(sy.totalSupply(), depositAmount - redeemAmount, "Total supply should decrease after redeem");
    }
}
