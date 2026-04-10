// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {NativeAmountMismatch} from "../../src/libraries/CommonErrors.sol";
import {IStandardizedYield} from "../../src/yield/interfaces/IStandardizedYield.sol";
import {OutrunAsBNBSY} from "../../src/yield/adapters/aster/OutrunAsBNBSY.sol";
import {
    MockAsBNB,
    MockAsBnbMinter,
    MockListaBNBStakeManager,
    MockSlisBNB,
    MockYieldProxy
} from "./mocks/AsterSYMocks.sol";

// 先把 adapter 对外 surface 和关键语义钉死；当前阶段允许因生产代码缺失而失败。
contract OutrunAsBNBSYTest is Test {
    address internal constant OWNER = address(0xA11CE);
    address internal constant USER = address(0xB0B);
    address internal constant OTHER = address(0xCAFE);
    address internal constant NATIVE = address(0);

    uint256 internal constant AMOUNT = 5 ether;
    uint256 internal constant SLIS_QUOTE = 0.97 ether;
    uint256 internal constant STAKE_RATIO = 0.98 ether;
    uint256 internal constant EXCHANGE_RATE_QUOTE = 1.03 ether;

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

        minter.setConvertToAsBnbQuote(SLIS_QUOTE);
        minter.setExchangeRateQuote(EXCHANGE_RATE_QUOTE);
        stakeManager.setQuote(STAKE_RATIO);

        sy = _deploySY(address(asBNB), address(slisBNB), address(minter));
    }

    function testConstructorCachesResolvedDependencies() external {
        assertEq(sy.AS_BNB_MINTER(), address(minter));
        assertEq(sy.SLIS_BNB(), address(slisBNB));
        assertEq(sy.YIELD_PROXY(), address(yieldProxy));
        assertEq(sy.STAKE_MANAGER(), address(stakeManager));
    }

    function testConstructorRevertsWhenAsBnbIsZero() external {
        vm.expectRevert(IStandardizedYield.SYZeroAddress.selector);
        _deploySY(address(0), address(slisBNB), address(minter));
    }

    function testConstructorRevertsWhenSlisBnbIsZero() external {
        vm.expectRevert(IStandardizedYield.SYZeroAddress.selector);
        _deploySY(address(asBNB), address(0), address(minter));
    }

    function testConstructorRevertsWhenMinterIsZero() external {
        vm.expectRevert(IStandardizedYield.SYZeroAddress.selector);
        _deploySY(address(asBNB), address(slisBNB), address(0));
    }

    function testConstructorRevertsWhenMinterAsBnbMismatches() external {
        minter.setAsBnb(OTHER);

        vm.expectRevert(abi.encodeWithSelector(OutrunAsBNBSY.InvalidAsBnbMinterAsBnb.selector, address(asBNB), OTHER));
        _deploySY(address(asBNB), address(slisBNB), address(minter));
    }

    function testConstructorRevertsWhenMinterTokenMismatches() external {
        minter.setToken(OTHER);

        vm.expectRevert(abi.encodeWithSelector(OutrunAsBNBSY.InvalidAsBnbMinterToken.selector, address(slisBNB), OTHER));
        _deploySY(address(asBNB), address(slisBNB), address(minter));
    }

    function testConstructorRevertsWhenYieldProxyIsZero() external {
        minter.setYieldProxy(address(0));

        vm.expectRevert(OutrunAsBNBSY.InvalidYieldProxy.selector);
        _deploySY(address(asBNB), address(slisBNB), address(minter));
    }

    function testConstructorRevertsWhenStakeManagerIsZero() external {
        yieldProxy.setStakeManager(address(0));

        vm.expectRevert(OutrunAsBNBSY.InvalidStakeManager.selector);
        _deploySY(address(asBNB), address(slisBNB), address(minter));
    }

    function testDepositAsBnbIsOneToOnePassthrough() external {
        asBNB.mint(USER, AMOUNT);

        vm.startPrank(USER);
        asBNB.approve(address(sy), AMOUNT);
        uint256 sharesOut = sy.deposit(USER, address(asBNB), AMOUNT, 0);
        vm.stopPrank();

        assertEq(sharesOut, AMOUNT);
        assertEq(sy.balanceOf(USER), AMOUNT);
        assertEq(asBNB.balanceOf(address(sy)), AMOUNT);
        assertEq(minter.lastMintAmount(), 0);
        assertEq(minter.lastNativeMintValue(), 0);
    }

    function testDepositSlisBnbMintsAsBnbViaMinter() external {
        slisBNB.mint(USER, AMOUNT);

        vm.startPrank(USER);
        slisBNB.approve(address(sy), AMOUNT);
        uint256 sharesOut = sy.deposit(USER, address(slisBNB), AMOUNT, 0);
        vm.stopPrank();

        uint256 expectedSharesOut = AMOUNT * SLIS_QUOTE / 1 ether;

        assertEq(sharesOut, expectedSharesOut);
        assertEq(sy.balanceOf(USER), expectedSharesOut);
        assertEq(minter.lastMintAmount(), AMOUNT);
        assertEq(asBNB.balanceOf(address(sy)), expectedSharesOut);
        assertEq(slisBNB.balanceOf(address(sy)), 0);
        assertGt(slisBNB.allowance(address(sy), address(minter)), 0);
        assertGt(slisBNB.approveCallCount(address(sy), address(minter)), 0);
    }

    function testSecondDepositSlisBnbReusesExistingAllowance() external {
        uint256 firstAmount = AMOUNT;
        uint256 secondAmount = AMOUNT / 2;
        uint256 expectedFirstSharesOut = firstAmount * SLIS_QUOTE / 1 ether;
        uint256 expectedSecondSharesOut = secondAmount * SLIS_QUOTE / 1 ether;

        slisBNB.mint(USER, firstAmount + secondAmount);

        vm.startPrank(USER);
        slisBNB.approve(address(sy), firstAmount + secondAmount);
        uint256 firstSharesOut = sy.deposit(USER, address(slisBNB), firstAmount, 0);

        uint256 approveCountAfterFirstDeposit = slisBNB.approveCallCount(address(sy), address(minter));
        assertEq(firstSharesOut, expectedFirstSharesOut);
        assertGt(approveCountAfterFirstDeposit, 0);
        assertGt(slisBNB.allowance(address(sy), address(minter)), 0);

        uint256 secondSharesOut = sy.deposit(USER, address(slisBNB), secondAmount, 0);
        vm.stopPrank();

        assertEq(secondSharesOut, expectedSecondSharesOut);
        assertEq(slisBNB.approveCallCount(address(sy), address(minter)), approveCountAfterFirstDeposit);
        assertGt(slisBNB.allowance(address(sy), address(minter)), 0);
        assertEq(sy.balanceOf(USER), expectedFirstSharesOut + expectedSecondSharesOut);
    }

    function testDepositNativeMintsAsBnbViaPayableMinter() external {
        vm.deal(USER, AMOUNT);

        vm.prank(USER);
        uint256 sharesOut = sy.deposit{value: AMOUNT}(USER, NATIVE, AMOUNT, 0);

        uint256 expectedSharesOut = AMOUNT * STAKE_RATIO / 1 ether * SLIS_QUOTE / 1 ether;

        assertEq(sharesOut, expectedSharesOut);
        assertEq(sy.balanceOf(USER), expectedSharesOut);
        assertEq(minter.lastNativeMintValue(), AMOUNT);
        assertEq(asBNB.balanceOf(address(sy)), expectedSharesOut);
    }

    function testDepositNativeRejectsMismatchedMsgValue() external {
        vm.deal(USER, AMOUNT);

        vm.prank(USER);
        vm.expectRevert(NativeAmountMismatch.selector);
        sy.deposit{value: AMOUNT - 1}(USER, NATIVE, AMOUNT, 0);
    }

    function testDepositSlisBnbMinSharesOutReverts() external {
        slisBNB.mint(USER, AMOUNT);
        uint256 expectedSharesOut = AMOUNT * SLIS_QUOTE / 1 ether;

        vm.startPrank(USER);
        slisBNB.approve(address(sy), AMOUNT);
        vm.expectRevert(
            abi.encodeWithSelector(
                IStandardizedYield.SYInsufficientSharesOut.selector, expectedSharesOut, expectedSharesOut + 1
            )
        );
        sy.deposit(USER, address(slisBNB), AMOUNT, expectedSharesOut + 1);
        vm.stopPrank();
    }

    function testDepositSlisBnbQueuedReverts() external {
        minter.setQueueMode(true);
        slisBNB.mint(USER, AMOUNT);

        vm.startPrank(USER);
        slisBNB.approve(address(sy), AMOUNT);
        vm.expectRevert(OutrunAsBNBSY.AsBnbMintQueued.selector);
        sy.deposit(USER, address(slisBNB), AMOUNT, 0);
        vm.stopPrank();

        assertEq(sy.balanceOf(USER), 0);
        assertEq(slisBNB.balanceOf(USER), AMOUNT);
        assertEq(asBNB.balanceOf(address(sy)), 0);
    }

    function testDepositNativeQueuedReverts() external {
        minter.setQueueMode(true);
        vm.deal(USER, AMOUNT);

        vm.prank(USER);
        vm.expectRevert(OutrunAsBNBSY.AsBnbMintQueued.selector);
        sy.deposit{value: AMOUNT}(USER, NATIVE, AMOUNT, 0);

        assertEq(sy.balanceOf(USER), 0);
        assertEq(asBNB.balanceOf(address(sy)), 0);
    }

    function testRedeemAsBnbIsOneToOnePassthrough() external {
        asBNB.mint(USER, AMOUNT);

        vm.startPrank(USER);
        asBNB.approve(address(sy), AMOUNT);
        sy.deposit(USER, address(asBNB), AMOUNT, 0);

        uint256 amountOut = sy.redeem(USER, AMOUNT, address(asBNB), 0, false);
        vm.stopPrank();

        assertEq(amountOut, AMOUNT);
        assertEq(sy.balanceOf(USER), 0);
        assertEq(asBNB.balanceOf(USER), AMOUNT);
    }

    function testRedeemAsBnbMinTokenOutReverts() external {
        asBNB.mint(USER, AMOUNT);

        vm.startPrank(USER);
        asBNB.approve(address(sy), AMOUNT);
        sy.deposit(USER, address(asBNB), AMOUNT, 0);

        vm.expectRevert(abi.encodeWithSelector(IStandardizedYield.SYInsufficientTokenOut.selector, AMOUNT, AMOUNT + 1));
        sy.redeem(USER, AMOUNT, address(asBNB), AMOUNT + 1, false);
        vm.stopPrank();
    }

    function testDepositInvalidTokenInReverts() external {
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(IStandardizedYield.SYInvalidTokenIn.selector, OTHER));
        sy.deposit(USER, OTHER, AMOUNT, 0);
    }

    function testPreviewDepositInvalidTokenInReverts() external {
        vm.expectRevert(abi.encodeWithSelector(IStandardizedYield.SYInvalidTokenIn.selector, OTHER));
        sy.previewDeposit(OTHER, AMOUNT);
    }

    function testPreviewDepositAsBnbIsOneToOne() external {
        assertEq(sy.previewDeposit(address(asBNB), AMOUNT), AMOUNT);
    }

    function testPreviewDepositSlisBnbUsesMinterQuote() external {
        uint256 previewShares = sy.previewDeposit(address(slisBNB), AMOUNT);

        assertEq(previewShares, AMOUNT * SLIS_QUOTE / 1 ether);
    }

    function testPreviewDepositNativeUsesStakeManagerThenMinter() external {
        uint256 previewShares = sy.previewDeposit(NATIVE, AMOUNT);

        assertEq(previewShares, AMOUNT * STAKE_RATIO / 1 ether * SLIS_QUOTE / 1 ether);
    }

    function testPreviewRedeemAsBnbIsOneToOne() external {
        assertEq(sy.previewRedeem(address(asBNB), AMOUNT), AMOUNT);
    }

    function testRedeemInvalidTokenOutReverts() external {
        asBNB.mint(USER, AMOUNT);

        vm.startPrank(USER);
        asBNB.approve(address(sy), AMOUNT);
        sy.deposit(USER, address(asBNB), AMOUNT, 0);

        vm.expectRevert(abi.encodeWithSelector(IStandardizedYield.SYInvalidTokenOut.selector, OTHER));
        sy.redeem(USER, AMOUNT, OTHER, 0, false);
        vm.stopPrank();
    }

    function testPreviewRedeemInvalidTokenOutReverts() external {
        vm.expectRevert(abi.encodeWithSelector(IStandardizedYield.SYInvalidTokenOut.selector, OTHER));
        sy.previewRedeem(OTHER, AMOUNT);
    }

    function testExchangeRateReadsConvertToTokensForOneShare() external {
        uint256 rate = sy.exchangeRate();

        assertEq(rate, EXCHANGE_RATE_QUOTE);
    }

    function testMetadataMatchesNativeCanonicalAssetAndSupportedTokens() external {
        address[] memory tokensIn = sy.getTokensIn();
        address[] memory tokensOut = sy.getTokensOut();

        assertEq(tokensIn.length, 3);
        assertEq(tokensIn[0], NATIVE);
        assertEq(tokensIn[1], address(slisBNB));
        assertEq(tokensIn[2], address(asBNB));

        assertEq(tokensOut.length, 1);
        assertEq(tokensOut[0], address(asBNB));

        assertTrue(sy.isValidTokenIn(NATIVE));
        assertTrue(sy.isValidTokenIn(address(slisBNB)));
        assertTrue(sy.isValidTokenIn(address(asBNB)));
        assertFalse(sy.isValidTokenIn(OTHER));

        assertTrue(sy.isValidTokenOut(address(asBNB)));
        assertFalse(sy.isValidTokenOut(NATIVE));
        assertFalse(sy.isValidTokenOut(address(slisBNB)));

        (IStandardizedYield.AssetType assetType, address assetAddress, uint8 assetDecimals) = sy.assetInfo();
        assertEq(uint256(assetType), uint256(IStandardizedYield.AssetType.TOKEN));
        assertEq(assetAddress, NATIVE);
        assertEq(assetDecimals, 18);
    }

    function _deploySY(address asBnb_, address slisBnb_, address minter_) internal returns (OutrunAsBNBSY) {
        return new OutrunAsBNBSY(OWNER, asBnb_, slisBnb_, minter_);
    }
}
