// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {NativeAmountMismatch} from "../../src/libraries/CommonErrors.sol";
import {SYUtils} from "../../src/libraries/SYUtils.sol";
import {IStandardizedYield} from "../../src/yield/interfaces/IStandardizedYield.sol";
import {IListaStakeManager} from "../../src/integrations/lista/interfaces/IListaStakeManager.sol";
import {OutrunSlisBNBSY} from "../../src/yield/adapters/lista/OutrunSlisBNBSY.sol";
import {MockListaSlisBNB, MockListaStakeManager, MockListaStakeManagerZeroDeposit} from "./mocks/ListaSYMocks.sol";

contract OutrunSlisBNBSYTest is Test {
    address internal constant OWNER = address(0xA11CE);
    address internal constant USER = address(0xB0B);
    address internal constant OTHER = address(0xCAFE);
    address internal constant NATIVE = address(0);

    uint256 internal constant AMOUNT = 5 ether;
    uint256 internal constant EXCHANGE_RATE_QUOTE = 0.98 ether;

    MockListaSlisBNB internal slisBNB;
    MockListaStakeManager internal stakeManager;
    OutrunSlisBNBSY internal sy;

    function setUp() external {
        slisBNB = new MockListaSlisBNB();
        stakeManager = new MockListaStakeManager(slisBNB);
        stakeManager.setExchangeRateQuote(EXCHANGE_RATE_QUOTE);

        sy = _deploySY(address(slisBNB), address(stakeManager));
    }

    // ── constructor ──────────────────────────────────────────────

    function testConstructorCachesStakeManager() external {
        assertEq(sy.STAKE_MANAGER(), address(stakeManager));
        assertEq(sy.yieldBearingToken(), address(slisBNB));
    }

    function testConstructorRevertsWhenSlisBnbIsZero() external {
        vm.expectRevert(IStandardizedYield.SYZeroAddress.selector);
        _deploySY(address(0), address(stakeManager));
    }

    function testConstructorRevertsWhenStakeManagerIsZero() external {
        vm.expectRevert(IStandardizedYield.SYZeroAddress.selector);
        _deploySY(address(slisBNB), address(0));
    }

    function testConstructorRevertsWhenSYZeroAddressBeforeDecimals() external {
        RevertingDecimalsToken revertingToken = new RevertingDecimalsToken();

        vm.expectRevert(IStandardizedYield.SYZeroAddress.selector);
        _deploySY(address(revertingToken), address(0));
    }

    // convertSnBnbToBnb(1e18) = 1e18 * 1e18 / 2e18 = 0.5e18 < 1e18
    function testConstructorRevertsWhenStakeManagerConvertReturnsBelowOne() external {
        MockListaStakeManager badStakeManager = new MockListaStakeManager(slisBNB);
        badStakeManager.setExchangeRateQuote(2 ether);

        vm.expectRevert(OutrunSlisBNBSY.InvalidStakeManager.selector);
        _deploySY(address(slisBNB), address(badStakeManager));
    }

    // ── deposit(BNB) ────────────────────────────────────────────

    function testDepositNativeMintsSlisBnbViaStakeManager() external {
        vm.deal(USER, AMOUNT);

        vm.prank(USER);
        uint256 sharesOut = sy.deposit{value: AMOUNT}(USER, NATIVE, AMOUNT, 0);

        // stakeManager mints slisBNB 1:1 with exchangeRateQuote applied:
        // sharesOut = AMOUNT * EXCHANGE_RATE_QUOTE / 1 ether
        uint256 expectedShares = AMOUNT * EXCHANGE_RATE_QUOTE / 1 ether;

        assertEq(sharesOut, expectedShares);
        assertEq(sy.balanceOf(USER), expectedShares);
        assertEq(slisBNB.balanceOf(address(sy)), expectedShares);
    }

    function testDepositNativeRejectsMismatchedMSGValue() external {
        vm.deal(USER, AMOUNT);

        vm.prank(USER);
        vm.expectRevert(NativeAmountMismatch.selector);
        sy.deposit{value: AMOUNT - 1}(USER, NATIVE, AMOUNT, 0);
    }

    function testDepositNativeZeroOutputReverts() external {
        MockListaStakeManagerZeroDeposit zeroDepositSM = new MockListaStakeManagerZeroDeposit(slisBNB);
        OutrunSlisBNBSY zeroSy = _deploySY(address(slisBNB), address(zeroDepositSM));

        vm.deal(USER, AMOUNT);

        vm.prank(USER);
        vm.expectRevert(OutrunSlisBNBSY.StakeManagerDepositZero.selector);
        zeroSy.deposit{value: AMOUNT}(USER, NATIVE, AMOUNT, 0);
    }

    function testDepositNativeMinSharesOutReverts() external {
        vm.deal(USER, AMOUNT);
        uint256 expectedShares = AMOUNT * EXCHANGE_RATE_QUOTE / 1 ether;

        vm.prank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(
                IStandardizedYield.SYInsufficientSharesOut.selector, expectedShares, expectedShares + 1
            )
        );
        sy.deposit{value: AMOUNT}(USER, NATIVE, AMOUNT, expectedShares + 1);
    }

    // ── deposit(slisBNB) ────────────────────────────────────────

    function testDepositSlisBnbIsOneToOnePassthrough() external {
        slisBNB.mint(USER, AMOUNT);

        vm.startPrank(USER);
        slisBNB.approve(address(sy), AMOUNT);
        uint256 sharesOut = sy.deposit(USER, address(slisBNB), AMOUNT, 0);
        vm.stopPrank();

        assertEq(sharesOut, AMOUNT);
        assertEq(sy.balanceOf(USER), AMOUNT);
        assertEq(slisBNB.balanceOf(address(sy)), AMOUNT);
    }

    // ── redeem ──────────────────────────────────────────────────

    function testRedeemSlisBnbIsOneToOnePassthrough() external {
        slisBNB.mint(USER, AMOUNT);

        vm.startPrank(USER);
        slisBNB.approve(address(sy), AMOUNT);
        sy.deposit(USER, address(slisBNB), AMOUNT, 0);

        uint256 amountOut = sy.redeem(USER, AMOUNT, address(slisBNB), 0, false);
        vm.stopPrank();

        assertEq(amountOut, AMOUNT);
        assertEq(sy.balanceOf(USER), 0);
        assertEq(slisBNB.balanceOf(USER), AMOUNT);
    }

    function testRedeemMinTokenOutReverts() external {
        slisBNB.mint(USER, AMOUNT);

        vm.startPrank(USER);
        slisBNB.approve(address(sy), AMOUNT);
        sy.deposit(USER, address(slisBNB), AMOUNT, 0);

        vm.expectRevert(abi.encodeWithSelector(IStandardizedYield.SYInsufficientTokenOut.selector, AMOUNT, AMOUNT + 1));
        sy.redeem(USER, AMOUNT, address(slisBNB), AMOUNT + 1, false);
        vm.stopPrank();
    }

    // ── preview / exchangeRate ──────────────────────────────────

    function testExchangeRateReturnsConvertSnBnbToBnb() external {
        uint256 rate = sy.exchangeRate();
        uint256 expected = IListaStakeManager(address(stakeManager)).convertSnBnbToBnb(1 ether);

        assertEq(rate, expected);
    }

    function testPreviewDepositSlisBnbIsOneToOne() external {
        assertEq(sy.previewDeposit(address(slisBNB), AMOUNT), AMOUNT);
    }

    function testPreviewDepositNativeUsesConvertBnbToSnBnb() external {
        uint256 previewShares = sy.previewDeposit(NATIVE, AMOUNT);
        uint256 expected = IListaStakeManager(address(stakeManager)).convertBnbToSnBnb(AMOUNT);

        assertEq(previewShares, expected);
    }

    function testPreviewDepositNativeClosesOverExchangeRate() external {
        uint256 nativeAmount = 1 ether;
        uint256 previewShares = sy.previewDeposit(NATIVE, nativeAmount);
        uint256 expectedShares = SYUtils.assetToSy(sy.exchangeRate(), nativeAmount);

        assertEq(previewShares, expectedShares);
    }

    function testPreviewRedeemSlisBnbIsOneToOne() external {
        assertEq(sy.previewRedeem(address(slisBNB), AMOUNT), AMOUNT);
    }

    // ── validation ──────────────────────────────────────────────

    function testDepositInvalidTokenInReverts() external {
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(IStandardizedYield.SYInvalidTokenIn.selector, OTHER));
        sy.deposit(USER, OTHER, AMOUNT, 0);
    }

    function testPreviewDepositInvalidTokenInReverts() external {
        vm.expectRevert(abi.encodeWithSelector(IStandardizedYield.SYInvalidTokenIn.selector, OTHER));
        sy.previewDeposit(OTHER, AMOUNT);
    }

    function testRedeemInvalidTokenOutReverts() external {
        slisBNB.mint(USER, AMOUNT);

        vm.startPrank(USER);
        slisBNB.approve(address(sy), AMOUNT);
        sy.deposit(USER, address(slisBNB), AMOUNT, 0);

        vm.expectRevert(abi.encodeWithSelector(IStandardizedYield.SYInvalidTokenOut.selector, OTHER));
        sy.redeem(USER, AMOUNT, OTHER, 0, false);
        vm.stopPrank();
    }

    function testPreviewRedeemInvalidTokenOutReverts() external {
        vm.expectRevert(abi.encodeWithSelector(IStandardizedYield.SYInvalidTokenOut.selector, OTHER));
        sy.previewRedeem(OTHER, AMOUNT);
    }

    // ── metadata ────────────────────────────────────────────────

    function testMetadataMatchesNativeCanonicalAssetAndSupportedTokens() external {
        address[] memory tokensIn = sy.getTokensIn();
        address[] memory tokensOut = sy.getTokensOut();

        assertEq(tokensIn.length, 2);
        assertEq(tokensIn[0], NATIVE);
        assertEq(tokensIn[1], address(slisBNB));

        assertEq(tokensOut.length, 1);
        assertEq(tokensOut[0], address(slisBNB));

        assertTrue(sy.isValidTokenIn(NATIVE));
        assertTrue(sy.isValidTokenIn(address(slisBNB)));
        assertFalse(sy.isValidTokenIn(OTHER));

        assertTrue(sy.isValidTokenOut(address(slisBNB)));
        assertFalse(sy.isValidTokenOut(NATIVE));
        assertFalse(sy.isValidTokenOut(OTHER));

        (IStandardizedYield.AssetType assetType, address assetAddress, uint8 assetDecimals) = sy.assetInfo();
        assertEq(uint256(assetType), uint256(IStandardizedYield.AssetType.TOKEN));
        assertEq(assetAddress, NATIVE);
        assertEq(assetDecimals, 18);
    }

    // ── helper ──────────────────────────────────────────────────

    function _deploySY(address slisBnb_, address stakeManager_) internal returns (OutrunSlisBNBSY) {
        return new OutrunSlisBNBSY(OWNER, slisBnb_, stakeManager_);
    }
}

contract RevertingDecimalsToken {
    function decimals() external pure returns (uint8) {
        revert("NO_DECIMALS");
    }
}
