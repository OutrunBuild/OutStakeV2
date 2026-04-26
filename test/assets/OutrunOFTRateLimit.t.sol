// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {MessagingFee} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {OFTLimit, OFTReceipt, SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {OutrunOFT} from "../../src/assets/omnichain/OutrunOFT.sol";
import {MockLzEndpoint, MockMsgInspector, OutrunOftHarness} from "./helpers/OFTTestHelper.sol";

contract OutrunOFTRateLimitTest is Test {
    using SafeCast for uint256;

    OutrunOftHarness internal oft;
    MockLzEndpoint internal endpoint;
    address internal owner = address(0xA11CE);
    address internal user = address(0xB0B);

    uint32 internal constant DST_EID = 1;

    function setUp() external {
        endpoint = new MockLzEndpoint();
        oft = new OutrunOftHarness("Outrun OFT", "OFT", 18, address(endpoint), owner);
        vm.prank(owner);
        oft.setMintingCap(user, 1000e18);
        vm.prank(user);
        oft.mint(user, 100e18);
    }

    function _toUint192(uint256 value) internal pure returns (uint192) {
        return value.toUint192();
    }

    // ── Admin setters ──────────────────────────────────────────────────────

    function testSetOutboundRateLimit() external {
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit OutrunOFT.OutboundRateLimitSet(DST_EID, 60e18, 1000);
        oft.setOutboundRateLimit(DST_EID, 60e18, 1000);

        (uint256 amountInFlight, uint256 lastUpdated, uint256 limit, uint256 window) = oft.rateLimits(DST_EID);
        assertEq(limit, 60e18);
        assertEq(amountInFlight, 0);
        assertEq(window, 1000);
        assertGt(lastUpdated, 0);
    }

    function testSetRateLimitRevertsIfNotOwner() external {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user));
        oft.setOutboundRateLimit(DST_EID, 60e18, 1000);
    }

    function testSetRateLimitRevertsOnZeroWindow() external {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("InvalidWindowSeconds()"));
        oft.setOutboundRateLimit(DST_EID, 60e18, 0);
    }

    // ── Remove ─────────────────────────────────────────────────────────────

    function testRemoveOutboundRateLimit() external {
        vm.startPrank(owner);
        oft.setOutboundRateLimit(DST_EID, 60e18, 1000);

        vm.expectEmit(true, false, false, true);
        emit OutrunOFT.OutboundRateLimitRemoved(DST_EID);
        oft.removeOutboundRateLimit(DST_EID);
        vm.stopPrank();

        (uint256 amountInFlight, uint256 lastUpdated, uint256 limit, uint256 window) = oft.rateLimits(DST_EID);
        assertEq(limit, 0);
        assertEq(amountInFlight, 0);
        assertEq(window, 0);
        assertEq(lastUpdated, 0);
    }

    function testRemoveOutboundRateLimitRevertsIfNotOwner() external {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user));
        oft.removeOutboundRateLimit(DST_EID);
    }

    // ── Unconfigured = no limit ────────────────────────────────────────────

    function testUnconfiguredPeerNoLimitOutbound() external {
        uint32 unconfiguredEid = 99;
        vm.prank(user);
        (uint256 sent, uint256 received) = oft.exposedDebit(user, 50e18, 0, unconfiguredEid);
        assertEq(sent, 50e18);
        assertEq(received, 50e18);
    }

    function testGetAmountCanBeSentUnconfiguredReturnsSharedDecimalEnvelope() external {
        uint32 unconfiguredEid = 99;
        uint256 sharedDecimalEnvelope = uint256(type(uint64).max) * oft.decimalConversionRate();
        (uint256 inFlight, uint256 canBeSent) = oft.getAmountCanBeSent(unconfiguredEid);
        assertEq(inFlight, 0);
        assertEq(canBeSent, sharedDecimalEnvelope);
    }

    function testGetAmountCanBeSentAfterRemoveReturnsSharedDecimalEnvelope() external {
        vm.prank(owner);
        oft.setOutboundRateLimit(DST_EID, 60e18, 1000);

        vm.prank(owner);
        oft.removeOutboundRateLimit(DST_EID);

        uint256 sharedDecimalEnvelope = uint256(type(uint64).max) * oft.decimalConversionRate();
        (uint256 inFlight, uint256 canBeSent) = oft.getAmountCanBeSent(DST_EID);
        assertEq(inFlight, 0);
        assertEq(canBeSent, sharedDecimalEnvelope);
    }

    // ── Basic pass / fail ─────────────────────────────────────────────────

    function testOutboundWithinLimit() external {
        vm.prank(owner);
        oft.setOutboundRateLimit(DST_EID, 60e18, 1000);

        vm.prank(user);
        oft.exposedDebit(user, 50e18, 0, DST_EID);

        (uint256 amountInFlight,, uint256 limit,) = oft.rateLimits(DST_EID);
        assertEq(amountInFlight, 50e18);
        assertEq(limit, 60e18);
    }

    function testOutboundExceedsLimit() external {
        vm.prank(owner);
        oft.setOutboundRateLimit(DST_EID, 40e18, 1000);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("RateLimitExceeded()"));
        oft.exposedDebit(user, 50e18, 0, DST_EID);
    }

    // ── Quote: reports capacity in oftLimit.maxAmountLD ────────────────────

    function testQuoteOFTLimitReportsLowerOfRateLimitAndSharedDecimalEnvelope() external {
        uint256 decimalConversionRate = oft.decimalConversionRate();
        uint256 sharedDecimalEnvelope = uint256(type(uint64).max) * decimalConversionRate;

        vm.prank(owner);
        oft.setOutboundRateLimit(DST_EID, _toUint192(sharedDecimalEnvelope + decimalConversionRate), 1000);

        SendParam memory sendParam = SendParam({
            dstEid: DST_EID,
            to: bytes32(uint256(uint160(user))),
            amountLD: sharedDecimalEnvelope,
            minAmountLD: 0,
            extraOptions: bytes(""),
            composeMsg: bytes(""),
            oftCmd: bytes("")
        });

        (OFTLimit memory oftLimit,, OFTReceipt memory oftReceipt) = oft.quoteOFT(sendParam);

        assertEq(oftLimit.maxAmountLD, sharedDecimalEnvelope);
        assertEq(oftReceipt.amountSentLD, sharedDecimalEnvelope);
        assertEq(oftReceipt.amountReceivedLD, sharedDecimalEnvelope);
    }

    function testQuoteOFTMaxAmountReflectsRemainingCapacity() external {
        vm.prank(owner);
        oft.setOutboundRateLimit(DST_EID, 100e18, 1000);

        // Consume 60e18
        vm.prank(user);
        oft.exposedDebit(user, 60e18, 0, DST_EID);

        SendParam memory sendParam = SendParam({
            dstEid: DST_EID,
            to: bytes32(uint256(uint160(user))),
            amountLD: 1e18,
            minAmountLD: 0,
            extraOptions: bytes(""),
            composeMsg: bytes(""),
            oftCmd: bytes("")
        });

        (OFTLimit memory oftLimit,,) = oft.quoteOFT(sendParam);

        // maxAmountLD should reflect remaining capacity (40e18)
        assertEq(oftLimit.maxAmountLD, 40e18);
    }

    function testDebitFailsWhenQuoteSucceedsButRateLimitExceeded() external {
        vm.prank(owner);
        oft.setOutboundRateLimit(DST_EID, 100e18, 1000);

        // Consume 60e18
        vm.prank(user);
        oft.exposedDebit(user, 60e18, 0, DST_EID);

        SendParam memory sendParam = SendParam({
            dstEid: DST_EID,
            to: bytes32(uint256(uint160(user))),
            amountLD: 50e18,
            minAmountLD: 0,
            extraOptions: bytes(""),
            composeMsg: bytes(""),
            oftCmd: bytes("")
        });

        // Quote succeeds (no rate limit check in quote)
        oft.quoteOFT(sendParam);

        // But actual debit fails
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("RateLimitExceeded()"));
        oft.exposedDebit(user, 50e18, 0, DST_EID);
    }

    function testQuoteSendWithinCapacityCallsInspectorAndEndpointQuote() external {
        MockMsgInspector inspector = new MockMsgInspector();
        uint256 nativeFee = 12345;

        vm.prank(owner);
        oft.setMsgInspector(address(inspector));
        endpoint.setQuoteNativeFee(nativeFee);
        vm.prank(owner);
        oft.setPeer(DST_EID, bytes32(uint256(uint160(address(oft)))));

        SendParam memory sendParam = SendParam({
            dstEid: DST_EID,
            to: bytes32(uint256(uint160(user))),
            amountLD: 50e18,
            minAmountLD: 0,
            extraOptions: bytes(""),
            composeMsg: bytes(""),
            oftCmd: bytes("")
        });

        vm.expectCall(address(inspector), abi.encodeWithSelector(MockMsgInspector.inspect.selector), 1);
        vm.expectCall(address(endpoint), abi.encodeWithSelector(MockLzEndpoint.quote.selector), 1);

        MessagingFee memory fee = oft.quoteSend(sendParam, false);

        assertEq(fee.nativeFee, nativeFee);
    }

    // ── Sliding window decay (LayerZero model: decay = limit * elapsed / window) ──

    function testSlidingWindowDecay() external {
        vm.warp(1000);
        vm.prank(owner);
        oft.setOutboundRateLimit(DST_EID, 100e18, 1000);

        // T=1000: send 60e18 → amountInFlight=60
        vm.prank(user);
        oft.exposedDebit(user, 60e18, 0, DST_EID);

        // T=1500: decay = 100*500/1000 = 50; currentInFlight = max(60-50, 0) = 10;
        // amountCanBeSent = 100-10 = 90; send 40 → amountInFlight = 10+40 = 50
        vm.warp(1500);
        vm.prank(user);
        oft.exposedDebit(user, 40e18, 0, DST_EID);

        (uint256 amountInFlight,,,) = oft.rateLimits(DST_EID);
        assertEq(amountInFlight, 50e18);
    }

    function testFullWindowExpiredResetsInFlight() external {
        // Mint extra tokens so user can cover both debits
        vm.prank(user);
        oft.mint(user, 80e18);

        vm.warp(1000);
        vm.prank(owner);
        oft.setOutboundRateLimit(DST_EID, 100e18, 100);

        // T=1000: send 60e18
        vm.prank(user);
        oft.exposedDebit(user, 60e18, 0, DST_EID);

        // T=1101: full window expired, capacity fully restored
        vm.warp(1101);
        vm.prank(user);
        oft.exposedDebit(user, 80e18, 0, DST_EID);

        (uint256 amountInFlight,,,) = oft.rateLimits(DST_EID);
        assertEq(amountInFlight, 80e18);
    }

    // ── Admin lowers limit mid-window ──────────────────────────────────────

    function testLowerLimitBelowInFlightAvailableZero() external {
        vm.warp(1000);
        vm.prank(owner);
        oft.setOutboundRateLimit(DST_EID, 100e18, 1000);

        // T=1000: send 60e18 → amountInFlight=60
        vm.prank(user);
        oft.exposedDebit(user, 60e18, 0, DST_EID);

        // T=1100: decay = 100*100/1000 = 10; currentInFlight = 60-10 = 50
        vm.warp(1100);
        vm.prank(owner);
        oft.setOutboundRateLimit(DST_EID, 40e18, 1000);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("RateLimitExceeded()"));
        oft.exposedDebit(user, 1e18, 0, DST_EID);
    }

    function testLowerLimitBelowInFlightOneNewWindowCanStillBeZeroThenRecovers() external {
        vm.warp(0);
        vm.prank(owner);
        oft.setOutboundRateLimit(DST_EID, 100e18, 30);

        vm.prank(user);
        oft.exposedDebit(user, 100e18, 0, DST_EID);

        vm.warp(15);
        vm.prank(owner);
        oft.setOutboundRateLimit(DST_EID, 10e18, 60);

        vm.warp(75);
        (uint256 currentInFlight, uint256 canBeSent) = oft.getAmountCanBeSent(DST_EID);
        assertEq(currentInFlight, 40e18);
        assertEq(canBeSent, 0);

        vm.warp(261);
        (currentInFlight, canBeSent) = oft.getAmountCanBeSent(DST_EID);
        assertEq(currentInFlight, 9e18);
        assertEq(canBeSent, 1e18);
    }

    // ── Setter preserves state ─────────────────────────────────────────────

    function testSetterPreservesInFlightAndTimestamp() external {
        vm.prank(owner);
        oft.setOutboundRateLimit(DST_EID, 100e18, 1000);

        vm.prank(user);
        oft.exposedDebit(user, 50e18, 0, DST_EID);

        uint256 tsBefore = block.timestamp;

        vm.prank(owner);
        oft.setOutboundRateLimit(DST_EID, 200e18, 2000);

        (uint256 amountInFlight, uint256 lastUpdated, uint256 limit, uint256 window) = oft.rateLimits(DST_EID);
        assertEq(limit, 200e18);
        assertEq(window, 2000);
        assertEq(amountInFlight, 50e18, "amountInFlight should be preserved");
        assertEq(lastUpdated, tsBefore, "lastUpdated should be preserved");
    }

    // ── Boundary: first call consumes exactly limit ──────────────────────────

    function testFirstCallConsumesExactLimit() external {
        vm.prank(owner);
        oft.setOutboundRateLimit(DST_EID, 100e18, 1000);

        vm.prank(user);
        oft.exposedDebit(user, 100e18, 0, DST_EID);

        (uint256 amountInFlight,,,) = oft.rateLimits(DST_EID);
        assertEq(amountInFlight, 100e18);
    }

    // ── Same-block consecutive calls: zero decay ────────────────────────────

    function testSameBlockConsecutiveCallsNoDecay() external {
        vm.prank(owner);
        oft.setOutboundRateLimit(DST_EID, 100e18, 1000);

        // First debit: 60e18
        vm.prank(user);
        oft.exposedDebit(user, 60e18, 0, DST_EID);

        // Second debit in same block: elapsed=0, no decay, available=40e18
        vm.prank(user);
        oft.exposedDebit(user, 40e18, 0, DST_EID);

        (uint256 amountInFlight,,,) = oft.rateLimits(DST_EID);
        assertEq(amountInFlight, 100e18);
    }

    // ── Remove then set: clean state ────────────────────────────────────────

    function testRemoveThenSetCleanState() external {
        vm.warp(1000);
        vm.prank(owner);
        oft.setOutboundRateLimit(DST_EID, 100e18, 1000);

        vm.prank(user);
        oft.exposedDebit(user, 60e18, 0, DST_EID);

        // Remove: clears all state
        vm.prank(owner);
        oft.removeOutboundRateLimit(DST_EID);

        // Re-set: should start fresh
        vm.prank(owner);
        oft.setOutboundRateLimit(DST_EID, 100e18, 500);

        (uint256 amountInFlight,, uint256 limit, uint256 window) = oft.rateLimits(DST_EID);
        assertEq(limit, 100e18);
        assertEq(amountInFlight, 0, "amountInFlight should be 0 after remove+set");
        assertEq(window, 500);

        // Mint more so user has enough for final debit
        vm.prank(user);
        oft.mint(user, 100e18);

        // Can consume full limit again
        vm.prank(user);
        oft.exposedDebit(user, 100e18, 0, DST_EID);
    }

    // ── LayerZero parity: multiple sends in one window ────────────────────────

    function testLayerZeroParity_MultipleSendsInWindow() external {
        vm.warp(0);
        vm.prank(owner);
        oft.setOutboundRateLimit(DST_EID, 100e18, 1000);

        // T=0: send 60 → amountInFlight=60, lastUpdated=0
        vm.prank(user);
        oft.exposedDebit(user, 60e18, 0, DST_EID);

        // T=500: decay = 100*500/1000 = 50; currentInFlight = max(60-50, 0) = 10;
        // amountCanBeSent = 100-10 = 90; send 40 → amountInFlight = 10+40 = 50
        vm.warp(500);
        vm.prank(user);
        oft.exposedDebit(user, 40e18, 0, DST_EID);

        (uint256 amountInFlight,,,) = oft.rateLimits(DST_EID);
        assertEq(amountInFlight, 50e18);

        // T=1000: decay = 100*500/1000 = 50; currentInFlight = max(50-50, 0) = 0;
        // amountCanBeSent = 100; full capacity restored
        vm.warp(1000);
        (uint256 currentInFlight, uint256 canBeSent) = oft.getAmountCanBeSent(DST_EID);
        assertEq(currentInFlight, 0);
        assertEq(canBeSent, 100e18);
    }

    // ── Pause interaction: rate-limit check runs before _update ─────────────

    function testPauseRateLimitExceededFirst() external {
        vm.prank(owner);
        oft.setOutboundRateLimit(DST_EID, 100e18, 1000);

        vm.prank(owner);
        oft.pause();

        // Amount exceeds rate limit → RateLimitExceeded fires BEFORE pause check
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("RateLimitExceeded()"));
        oft.exposedDebit(user, 200e18, 0, DST_EID);

        // Amount within rate limit → pause blocks the _burn
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        oft.exposedDebit(user, 50e18, 0, DST_EID);
    }

    // ── limit=0 blocks all transfers ────────────────────────────────────────

    function testOutboundLimitZeroBlocksAll() external {
        vm.prank(owner);
        oft.setOutboundRateLimit(DST_EID, 0, 1000);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("RateLimitExceeded()"));
        oft.exposedDebit(user, 1e18, 0, DST_EID);
    }

    // ── Independent dstEids ──────────────────────────────────────────────────

    function testIndependentDstEids() external {
        uint32 eid1 = DST_EID;
        uint32 eid2 = DST_EID + 1;

        vm.startPrank(owner);
        oft.setOutboundRateLimit(eid1, 50e18, 1000);
        oft.setOutboundRateLimit(eid2, 50e18, 1000);
        vm.stopPrank();

        // Max out eid1
        vm.prank(user);
        oft.exposedDebit(user, 50e18, 0, eid1);

        // eid2 still has full capacity
        vm.prank(user);
        oft.exposedDebit(user, 50e18, 0, eid2);

        // eid1 blocked
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("RateLimitExceeded()"));
        oft.exposedDebit(user, 1e18, 0, eid1);

        // eid2 also blocked
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("RateLimitExceeded()"));
        oft.exposedDebit(user, 1e18, 0, eid2);
    }

    // ── Boundary: decay at exact window edges ──────────────────────────────────

    function testDecayAtExactWindowBoundary() external {
        vm.warp(0);
        vm.prank(owner);
        oft.setOutboundRateLimit(DST_EID, 100e18, 1000);

        vm.prank(user);
        oft.exposedDebit(user, 100e18, 0, DST_EID);

        // At exact window boundary: full capacity restored
        vm.warp(1000);
        (uint256 inflight, uint256 canSend) = oft.getAmountCanBeSent(DST_EID);
        assertEq(inflight, 0);
        assertEq(canSend, 100e18);

        // Mint more for second debit
        vm.prank(user);
        oft.mint(user, 100e18);

        // One second before next window expires: not yet restored
        vm.prank(user);
        oft.exposedDebit(user, 100e18, 0, DST_EID);

        vm.warp(1999);
        (inflight, canSend) = oft.getAmountCanBeSent(DST_EID);
        assertGt(inflight, 0);
        assertLt(canSend, 100e18);
    }

    // ── Fuzz: debit + quoteOFT consistency ───────────────────────────────────

    function testFuzz_QuoteOFTMaxAmountMatchesRemainingCapacity(uint256 limit_, uint64 window, uint256 consumed_)
        external
    {
        // Align to decimalConversionRate to avoid dust mismatch
        uint256 rate = oft.decimalConversionRate();
        uint256 limit = bound(limit_, rate, 100e18) / rate * rate;
        vm.assume(limit >= rate);
        vm.assume(window > 0);
        uint256 consumed = bound(consumed_, 0, limit) / rate * rate;

        vm.prank(user);
        oft.mint(user, limit);

        vm.prank(owner);
        oft.setOutboundRateLimit(DST_EID, _toUint192(limit), window);

        if (consumed > 0) {
            vm.prank(user);
            oft.exposedDebit(user, consumed, 0, DST_EID);
        }

        SendParam memory sendParam = SendParam({
            dstEid: DST_EID,
            to: bytes32(uint256(uint160(user))),
            amountLD: rate,
            minAmountLD: 0,
            extraOptions: bytes(""),
            composeMsg: bytes(""),
            oftCmd: bytes("")
        });

        (OFTLimit memory oftLimit,,) = oft.quoteOFT(sendParam);

        uint256 envelope = uint256(type(uint64).max) * rate;
        uint256 expected = limit - consumed;
        if (expected > envelope) expected = envelope;
        assertEq(oftLimit.maxAmountLD, expected);
    }

    // ── Fuzz: time decay invariant ───────────────────────────────────────────

    function testFuzz_TimeDecayInvariant(uint256 limit_, uint64 window, uint256 elapsed) external {
        uint256 rate = oft.decimalConversionRate();
        uint256 limit = bound(limit_, rate, 100e18) / rate * rate;
        vm.assume(limit >= rate);
        vm.assume(window > 0);
        vm.assume(elapsed > 0 && elapsed <= uint256(window) * 2);

        vm.warp(0);
        vm.prank(owner);
        oft.setOutboundRateLimit(DST_EID, _toUint192(limit), window);

        vm.prank(user);
        oft.mint(user, limit);

        vm.prank(user);
        oft.exposedDebit(user, limit, 0, DST_EID);

        vm.warp(elapsed);

        (uint256 inflight, uint256 canSend) = oft.getAmountCanBeSent(DST_EID);

        if (elapsed >= window) {
            assertEq(inflight, 0);
            assertEq(canSend, limit);
        } else {
            assertLe(inflight, limit);
            assertEq(inflight + canSend, limit);
        }
    }

    // ── Fuzz: independent EIDs ──────────────────────────────────────────────

    function testFuzz_IndependentEids(uint32 eid1, uint32 eid2, uint256 amount1_, uint256 amount2_) external {
        vm.assume(eid1 != eid2);
        uint256 rate = oft.decimalConversionRate();
        uint256 limit = 100e18;
        uint256 amount1 = bound(amount1_, rate, limit) / rate * rate;
        uint256 amount2 = bound(amount2_, rate, limit) / rate * rate;

        vm.prank(user);
        oft.mint(user, limit);

        vm.startPrank(owner);
        oft.setOutboundRateLimit(eid1, _toUint192(limit), 1000);
        oft.setOutboundRateLimit(eid2, _toUint192(limit), 1000);
        vm.stopPrank();

        vm.prank(user);
        oft.exposedDebit(user, amount1, 0, eid1);
        vm.prank(user);
        oft.exposedDebit(user, amount2, 0, eid2);

        (uint256 inflight1, uint256 canSend1) = oft.getAmountCanBeSent(eid1);
        (uint256 inflight2, uint256 canSend2) = oft.getAmountCanBeSent(eid2);

        assertEq(inflight1, amount1);
        assertEq(canSend1, limit - amount1);
        assertEq(inflight2, amount2);
        assertEq(canSend2, limit - amount2);
    }
}
