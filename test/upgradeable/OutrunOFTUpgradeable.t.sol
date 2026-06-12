// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";
import {MessagingFee, OFTLimit, SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {OutrunUniversalAssetsUpgradeable} from "../../src/assets/base/OutrunUniversalAssetsUpgradeable.sol";
import {OutrunRateLimiterUpgradeable} from "../../src/assets/omnichain/OutrunRateLimiterUpgradeable.sol";
import {MockLzEndpoint, OutrunUpgradeableOftHarness} from "./mocks/OFTMocks.sol";
import {ProxyTestHelper} from "./helpers/ProxyTestHelper.sol";

contract OutrunOFTUpgradeableTest is Test {
    OutrunUpgradeableOftHarness internal oft;
    OutrunUniversalAssetsUpgradeable internal uAsset;
    MockLzEndpoint internal endpoint;

    address internal owner = address(0xA11CE);
    address internal user = address(0xB0B);
    uint32 internal constant DST_EID = 101;

    function setUp() external {
        endpoint = new MockLzEndpoint();

        // Deploy the real OutrunUniversalAssetsUpgradeable for minting-cap tests.
        OutrunUniversalAssetsUpgradeable uAssetImpl = new OutrunUniversalAssetsUpgradeable(18, address(endpoint));
        uAsset = OutrunUniversalAssetsUpgradeable(
            ProxyTestHelper.deploy(
                address(uAssetImpl),
                abi.encodeCall(OutrunUniversalAssetsUpgradeable.initialize, ("Outrun OFT", "OFT", 18, owner))
            )
        );

        // Deploy the harness (OutrunOFTUpgradeable child) for debit/credit/outflow tests.
        OutrunUpgradeableOftHarness implementation = new OutrunUpgradeableOftHarness(18, address(endpoint));
        oft = OutrunUpgradeableOftHarness(
            ProxyTestHelper.deploy(
                address(implementation),
                abi.encodeCall(OutrunUpgradeableOftHarness.initialize, ("Outrun OFT", "OFT", 18, owner))
            )
        );

        // Set up the real uAsset for minting-cap tests.
        vm.prank(owner);
        uAsset.setMintingCap(user, 100e18);
        vm.prank(user);
        uAsset.mint(user, 100e18);

        // Mint tokens on the harness for debit/credit/outflow tests.
        oft.exposedCredit(user, 100e18, 0);
    }

    function testTokenAndApprovalRequiredUseLocalToken() external {
        assertEq(oft.token(), address(oft));
        assertFalse(oft.approvalRequired());
    }

    function testUnconfiguredPeerDebitIsNotRateLimited() external {
        vm.prank(user);
        (uint256 sent, uint256 received) = oft.exposedDebit(user, 25e18, 0, DST_EID);

        OutrunRateLimiterUpgradeable.RateLimit memory rateLimit = oft.rateLimits(DST_EID);
        assertEq(sent, 25e18);
        assertEq(received, 25e18);
        assertEq(oft.balanceOf(user), 75e18);
        assertEq(oft.outflowCalls(), 1);
        assertEq(rateLimit.amountInFlight, 0);
        assertEq(rateLimit.lastUpdated, 0);
        assertEq(rateLimit.limit, 0);
        assertEq(rateLimit.window, 0);
    }

    function testQuoteLimitReflectsConfiguredRateLimit() external {
        vm.prank(owner);
        oft.setOutboundRateLimit(DST_EID, 40e18, 1 days);

        vm.prank(user);
        oft.exposedDebit(user, 25e18, 0, DST_EID);

        (OFTLimit memory oftLimit,,) = oft.quoteOFT(_sendParam(100e18));
        assertEq(oftLimit.maxAmountLD, 15e18);
    }

    function testSetOutboundRateLimitDoesNotDispatchVirtualOutflow() external {
        vm.prank(owner);
        oft.setOutboundRateLimit(DST_EID, 40e18, 1 days);

        assertEq(oft.outflowCalls(), 0);
    }

    function testDebitDispatchesVirtualOutflow() external {
        vm.prank(owner);
        oft.setOutboundRateLimit(DST_EID, 40e18, 1 days);

        vm.prank(user);
        oft.exposedDebit(user, 25e18, 0, DST_EID);

        assertEq(oft.outflowCalls(), 1);
    }

    function testPausedTokenBlocksNewOutboundDebit() external {
        vm.prank(owner);
        oft.pause();

        vm.prank(user);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        oft.exposedDebit(user, 25e18, 0, DST_EID);
    }

    function testPausedTokenBlocksNewOutboundSend() external {
        vm.prank(owner);
        oft.setPeer(DST_EID, bytes32(uint256(uint160(address(oft)))));

        vm.prank(owner);
        oft.pause();

        vm.prank(user);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        oft.send(_sendParam(25e18), MessagingFee({nativeFee: 0, lzTokenFee: 0}), user);
    }

    function testPausedTokenAllowsInboundCredit() external {
        vm.prank(owner);
        oft.pause();

        uint256 received = oft.exposedCredit(user, 25e18, DST_EID);

        assertEq(received, 25e18);
        assertEq(oft.balanceOf(user), 125e18);
    }

    function testAmountCanBeSentResetsWhenWindowElapsed() external {
        vm.prank(owner);
        oft.setOutboundRateLimit(DST_EID, 40e18, 1 days);

        vm.prank(user);
        oft.exposedDebit(user, 25e18, 0, DST_EID);

        vm.warp(block.timestamp + 1 days);

        (uint256 inFlight, uint256 canBeSent) = oft.getAmountCanBeSent(DST_EID);
        assertEq(inFlight, 0);
        assertEq(canBeSent, 40e18);
    }

    function testMaxRateLimitBoundaryDoesNotOverflow() external {
        uint64 window = type(uint64).max;

        vm.prank(owner);
        oft.setOutboundRateLimit(DST_EID, type(uint192).max, window);

        vm.prank(user);
        oft.exposedDebit(user, oft.decimalConversionRate(), 0, DST_EID);

        vm.warp(block.timestamp + uint256(window) + 2);

        (uint256 inFlight, uint256 canBeSent) = oft.getAmountCanBeSent(DST_EID);
        assertEq(inFlight, 0);
        assertEq(canBeSent, type(uint192).max);
    }

    function testRemoveLimitRestoresSharedDecimalEnvelope() external {
        vm.startPrank(owner);
        oft.setOutboundRateLimit(DST_EID, 40e18, 1 days);
        oft.removeOutboundRateLimit(DST_EID);
        vm.stopPrank();

        (uint256 inFlight, uint256 canBeSent) = oft.getAmountCanBeSent(DST_EID);
        assertEq(inFlight, 0);
        assertEq(canBeSent, uint256(type(uint64).max) * oft.decimalConversionRate());
    }

    function _sendParam(uint256 amountLD) internal pure returns (SendParam memory) {
        return SendParam({
            dstEid: DST_EID,
            to: bytes32(uint256(uint160(address(0xBEEF)))),
            amountLD: amountLD,
            minAmountLD: 0,
            extraOptions: bytes(""),
            composeMsg: bytes(""),
            oftCmd: bytes("")
        });
    }
}
