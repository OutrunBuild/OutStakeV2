// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {
    MessagingFee,
    MessagingParams
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

import {SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";

import {OutrunUniversalAssets} from "../../src/assets/base/OutrunUniversalAssets.sol";

import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

error AmountSDOverflowed(uint256 amountSD);

/// @title MockLzEndpoint
/// @notice Reuses the existing mock from OutrunUniversalAssets.t.sol
contract MockLzEndpoint {
    address internal delegate;
    uint256 internal quoteNativeFee;

    function setDelegate(address delegate_) external {
        delegate = delegate_;
    }

    function setQuoteNativeFee(uint256 nativeFee_) external {
        quoteNativeFee = nativeFee_;
    }

    function quote(MessagingParams calldata, address) external view returns (MessagingFee memory fee) {
        fee = MessagingFee({nativeFee: quoteNativeFee, lzTokenFee: 0});
    }

    function send(MessagingParams calldata, address) external payable returns (MessagingFee memory) {
        return MessagingFee({nativeFee: quoteNativeFee, lzTokenFee: 0});
    }
}

/// @title OutrunOftHarness
/// @notice Concrete implementation of OutrunOFT that exposes internal functions for testing
contract OutrunOftHarness is OutrunUniversalAssets {
    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        address _lzEndpoint,
        address _delegate,
        address flashFeeReceiver
    ) OutrunUniversalAssets(name_, symbol_, decimals_, _lzEndpoint, _delegate, flashFeeReceiver) {}

    /// @dev Expose _credit for testing
    function exposedCredit(address to, uint256 amountLD, uint32 srcEid) external returns (uint256) {
        return _credit(to, amountLD, srcEid);
    }

    /// @dev Expose _debit for testing
    function exposedDebit(address from, uint256 amountLD, uint256 minAmountLD, uint32 dstEid)
        external
        returns (uint256 amountSentLD, uint256 amountReceivedLD)
    {
        return _debit(from, amountLD, minAmountLD, dstEid);
    }

    /// @dev Expose _toSD for testing
    function exposedToSD(uint256 amountLD) external view returns (uint64) {
        return _toSD(amountLD);
    }
}

/// @title OutrunOFTTest
/// @notice Tests for OutrunOFT contract functionality
contract OutrunOFTTest is Test {
    OutrunOftHarness internal sy;
    MockLzEndpoint internal endpoint;
    address internal owner = address(0xA11CE);
    address internal user = address(0xB0B);
    address internal minter = address(0xB0B);
    address internal flashFeeReceiver = address(0xFEE);

    function setUp() external {
        endpoint = new MockLzEndpoint();
        sy = new OutrunOftHarness("Outrun OFT", "OFT", 18, address(endpoint), owner, flashFeeReceiver);
        vm.prank(owner);
        sy.setMintingCap(minter, 1000e18);
        vm.prank(minter);
        sy.mint(user, 100e18);
    }

    // ============================================
    // token() returns self address
    // ============================================
    function testTokenReturnsSelfAddress() external {
        assertEq(sy.token(), address(sy), "token() should return address(this)");
    }

    // ============================================
    // approvalRequired() returns false
    // ============================================
    function testApprovalRequiredReturnsFalse() external {
        assertFalse(sy.approvalRequired(), "approvalRequired() should return false for OFT");
    }

    function testCreditMintsTokensToRecipient() external {
        uint256 amount = 50e18;
        uint256 balanceBefore = sy.balanceOf(user);

        vm.prank(address(sy));
        sy.exposedCredit(user, amount, 1);

        assertEq(sy.balanceOf(user), balanceBefore + amount, "user should receive minted tokens");
    }

    function testCreditRedirectsZeroAddressToDead() external {
        uint256 amount = 50e18;
        uint256 deadBalanceBefore = sy.balanceOf(address(0xdead));
        uint256 totalSupplyBefore = sy.totalSupply();

        vm.prank(address(sy));
        sy.exposedCredit(address(0), amount, 1);

        assertEq(sy.balanceOf(address(0xdead)), deadBalanceBefore + amount, "0xdead should receive tokens");
        assertEq(sy.totalSupply(), totalSupplyBefore + amount, "totalSupply should increase");
    }

    function testDebitBurnsTokens() external {
        uint256 amount = 50e18;
        uint256 balanceBefore = sy.balanceOf(user);
        uint256 supplyBefore = sy.totalSupply();

        vm.prank(user);
        sy.exposedDebit(user, amount, 0, 1);

        assertEq(sy.balanceOf(user), balanceBefore - amount, "user tokens should be burned");
        assertEq(sy.totalSupply(), supplyBefore - amount, "totalSupply should decrease");
    }

    function testToSDNormalConversion() external {
        // For 18-decimal token with shared decimals = 8, decimalConversionRate = 1e10
        // So _toSD(1000e18) = 1000e18 / 1e10 = 1000e8
        uint256 amount = 1000e18;
        uint64 result = sy.exposedToSD(amount);
        assertGt(result, 0, "_toSD should return non-zero for valid amount");
        assertLe(result, type(uint64).max, "_toSD should not overflow for valid amount");
    }

    function testToSDRevertsOnOverflow() external {
        // _toSD divides by decimalConversionRate then checks > uint64.max
        // Build an amount whose division result exceeds uint64.max
        uint256 overflowAmount = (uint256(type(uint64).max) + 1) * sy.decimalConversionRate();
        vm.expectRevert();
        sy.exposedToSD(overflowAmount);
    }
}
