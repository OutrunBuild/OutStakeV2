// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {OFTLimit, SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {MockLzEndpoint, OutrunOftHarness} from "./helpers/OFTTestHelper.sol";

contract OutrunOFTTest is Test {
    OutrunOftHarness internal oft;
    MockLzEndpoint internal endpoint;
    address internal owner = address(0xA11CE);
    address internal user = address(0xB0B);
    address internal minter = address(0xB0B);

    function setUp() external {
        endpoint = new MockLzEndpoint();
        oft = new OutrunOftHarness("Outrun OFT", "OFT", 18, address(endpoint), owner);
        vm.prank(owner);
        oft.setMintingCap(minter, 1000e18);
        vm.prank(minter);
        oft.mint(user, 100e18);
    }

    function testTokenReturnsSelfAddress() external {
        assertEq(oft.token(), address(oft), "token() should return address(this)");
    }

    function testApprovalRequiredReturnsFalse() external {
        assertFalse(oft.approvalRequired(), "approvalRequired() should return false for OFT");
    }

    function testCreditMintsTokensToRecipient() external {
        uint256 amount = 50e18;
        uint256 balanceBefore = oft.balanceOf(user);

        vm.prank(address(oft));
        oft.exposedCredit(user, amount, 1);

        assertEq(oft.balanceOf(user), balanceBefore + amount, "user should receive minted tokens");
    }

    function testCreditRedirectsZeroAddressToDead() external {
        uint256 amount = 50e18;
        uint256 deadBalanceBefore = oft.balanceOf(address(0xdead));
        uint256 totalSupplyBefore = oft.totalSupply();

        vm.prank(address(oft));
        oft.exposedCredit(address(0), amount, 1);

        assertEq(oft.balanceOf(address(0xdead)), deadBalanceBefore + amount, "0xdead should receive tokens");
        assertEq(oft.totalSupply(), totalSupplyBefore + amount, "totalSupply should increase");
    }

    function testDebitBurnsTokens() external {
        uint256 amount = 50e18;
        uint256 balanceBefore = oft.balanceOf(user);
        uint256 supplyBefore = oft.totalSupply();

        vm.prank(user);
        oft.exposedDebit(user, amount, 0, 1);

        assertEq(oft.balanceOf(user), balanceBefore - amount, "user tokens should be burned");
        assertEq(oft.totalSupply(), supplyBefore - amount, "totalSupply should decrease");
    }

    function testToSDNormalConversion() external {
        uint256 amount = 1000e18;
        uint64 result = oft.exposedToSD(amount);
        assertGt(result, 0, "_toSD should return non-zero for valid amount");
        assertLe(result, type(uint64).max, "_toSD should not overflow for valid amount");
    }

    function testToSDRevertsOnOverflow() external {
        uint256 overflowAmount = (uint256(type(uint64).max) + 1) * oft.decimalConversionRate();
        vm.expectRevert(abi.encodeWithSignature("AmountSDOverflowed(uint256)", (uint256(type(uint64).max) + 1)));
        oft.exposedToSD(overflowAmount);
    }

    function testQuoteOFTReportsSharedDecimalEnvelopeAsMaxAmountForUnconfiguredPeer() external {
        SendParam memory sendParam = SendParam({
            dstEid: 1,
            to: bytes32(uint256(uint160(user))),
            amountLD: 100e18,
            minAmountLD: 0,
            extraOptions: bytes(""),
            composeMsg: bytes(""),
            oftCmd: bytes("")
        });

        (OFTLimit memory oftLimit,,) = oft.quoteOFT(sendParam);

        uint256 expectedEnvelope = uint256(type(uint64).max) * oft.decimalConversionRate();
        assertEq(oftLimit.minAmountLD, 0);
        assertEq(oftLimit.maxAmountLD, expectedEnvelope);
    }
}
