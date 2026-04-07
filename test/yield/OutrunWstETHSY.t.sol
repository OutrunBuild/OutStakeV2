// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {OutrunERC20} from "../../src/assets/base/OutrunERC20.sol";
import {IStandardizedYield} from "../../src/yield/interfaces/IStandardizedYield.sol";
import {OutrunWstETHSY} from "../../src/yield/adapters/lido/OutrunWstETHSY.sol";

contract MockLidoStETH is OutrunERC20 {
    error UnexpectedSelector(bytes4 selector);

    address internal submitReferral;
    uint256 internal submitValue;

    constructor() OutrunERC20("Liquid staked Ether 2.0", "stETH", 18) {}

    function submit(address referral) external payable returns (uint256 sharesOut) {
        submitReferral = referral;
        submitValue = msg.value;
        sharesOut = msg.value;
        _mint(msg.sender, sharesOut);
    }

    function getSharesByPooledEth(uint256 ethAmount) external pure returns (uint256) {
        return ethAmount;
    }

    function getPooledEthByShares(uint256 shareAmount) external pure returns (uint256) {
        return shareAmount;
    }

    function lastSubmitReferral() external view returns (address) {
        return submitReferral;
    }

    function lastSubmitValue() external view returns (uint256) {
        return submitValue;
    }

    fallback() external payable {
        revert UnexpectedSelector(msg.sig);
    }

    receive() external payable {}
}

contract MockWrappedStETH is OutrunERC20 {
    MockLidoStETH internal immutable stETH;

    constructor(address payable stETH_) OutrunERC20("Wrapped liquid staked Ether 2.0", "wstETH", 18) {
        stETH = MockLidoStETH(stETH_);
    }

    function stEthPerToken() external pure returns (uint256) {
        return 1e18;
    }

    function getWstETHByStETH(uint256 stETHAmount) external pure returns (uint256) {
        return stETHAmount;
    }

    function getStETHByWstETH(uint256 wstETHAmount) external pure returns (uint256) {
        return wstETHAmount;
    }

    function wrap(uint256 stETHAmount) external returns (uint256 wstETHAmount) {
        wstETHAmount = stETHAmount;
        stETH.transferFrom(msg.sender, address(this), stETHAmount);
        _mint(msg.sender, wstETHAmount);
    }

    function unwrap(uint256 wstETHAmount) external returns (uint256 stETHAmount) {
        stETHAmount = wstETHAmount;
        _burn(msg.sender, wstETHAmount);
        stETH.transfer(msg.sender, stETHAmount);
    }
}

contract OutrunWstETHSYTest is Test {
    address internal constant OWNER = address(0xA11CE);
    address internal constant USER = address(0xB0B);

    uint256 internal constant AMOUNT = 5 ether;

    MockLidoStETH internal stETH;
    MockWrappedStETH internal wstETH;
    OutrunWstETHSY internal sy;

    function setUp() external {
        stETH = new MockLidoStETH();
        wstETH = new MockWrappedStETH(payable(address(stETH)));
        sy = new OutrunWstETHSY(OWNER, address(stETH), address(wstETH));

        vm.deal(USER, AMOUNT);
    }

    function testDepositNativeUsesNoReferralSubmitSelector() external {
        vm.prank(USER);
        uint256 sharesOut = sy.deposit{value: AMOUNT}(USER, address(0), AMOUNT, 0);

        assertEq(sharesOut, AMOUNT);
        assertEq(sy.balanceOf(USER), AMOUNT);
        assertEq(stETH.lastSubmitReferral(), address(0));
        assertEq(stETH.lastSubmitValue(), AMOUNT);
    }

    function testDepositNativeSlippageReverts() external {
        uint256 slippageMinShares = AMOUNT + 1;

        vm.prank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(IStandardizedYield.SYInsufficientSharesOut.selector, AMOUNT, slippageMinShares)
        );
        sy.deposit{value: AMOUNT}(USER, address(0), AMOUNT, slippageMinShares);
    }

    function testRedeemToStETHSlippageReverts() external {
        vm.prank(USER);
        sy.deposit{value: AMOUNT}(USER, address(0), AMOUNT, 0);

        uint256 minTokenOut = AMOUNT + 1;
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(IStandardizedYield.SYInsufficientTokenOut.selector, AMOUNT, minTokenOut));
        sy.redeem(USER, AMOUNT, address(stETH), minTokenOut, false);
    }

    function testDepositStETHWrapsIntoWstETH() external {
        // USER needs stETH first
        vm.startPrank(USER);
        stETH.submit{value: AMOUNT}(address(0));

        uint256 stETHBalanceBefore = stETH.balanceOf(USER);
        uint256 wstETHBalanceBefore = wstETH.balanceOf(USER);

        stETH.approve(address(sy), AMOUNT);
        uint256 sharesOut = sy.deposit(USER, address(stETH), AMOUNT, 0);
        vm.stopPrank();

        assertEq(sharesOut, AMOUNT, "STETH deposit should use wrap");
        assertEq(sy.balanceOf(USER), AMOUNT);
        assertEq(stETH.balanceOf(USER), stETHBalanceBefore - AMOUNT);
        assertEq(wstETH.balanceOf(USER), wstETHBalanceBefore);
        assertEq(wstETH.balanceOf(address(sy)), AMOUNT);
    }

    function testDepositWstETHPassthrough() external {
        // USER needs stETH then wstETH
        vm.startPrank(USER);
        stETH.submit{value: AMOUNT}(address(0));
        stETH.approve(address(wstETH), AMOUNT);
        wstETH.wrap(AMOUNT);

        wstETH.balanceOf(USER);
        wstETH.approve(address(sy), AMOUNT);
        uint256 sharesOut = sy.deposit(USER, address(wstETH), AMOUNT, 0);
        vm.stopPrank();

        assertEq(sharesOut, AMOUNT, "wstETH deposit should be 1:1");
        assertEq(sy.balanceOf(USER), AMOUNT);
    }

    function testRedeemToWstETHPassthrough() external {
        vm.startPrank(USER);
        stETH.submit{value: AMOUNT}(address(0));
        stETH.approve(address(wstETH), AMOUNT);
        wstETH.wrap(AMOUNT);
        wstETH.approve(address(sy), AMOUNT);
        uint256 sharesOut = sy.deposit(USER, address(wstETH), AMOUNT, 0);

        uint256 wstETHBalanceBefore = wstETH.balanceOf(USER);
        uint256 amountOut = sy.redeem(USER, sharesOut, address(wstETH), 0, false);
        vm.stopPrank();

        assertEq(amountOut, sharesOut, "redeem to wstETH should be 1:1");
        assertEq(wstETH.balanceOf(USER), wstETHBalanceBefore + amountOut);
        assertEq(sy.balanceOf(USER), 0);
    }

    function testExchangeRateReadsStEthPerToken() external {
        uint256 rate = sy.exchangeRate();
        assertEq(rate, 1e18, "exchangeRate should return stEthPerToken");
    }

    function testPreviewDepositNATIVE() external {
        uint256 previewShares = sy.previewDeposit(address(0), AMOUNT);
        assertEq(previewShares, AMOUNT, "preview should return 1:1 at 1:1 rate");
    }

    function testPreviewDepositSTETH() external {
        uint256 previewShares = sy.previewDeposit(address(stETH), AMOUNT);
        assertEq(previewShares, AMOUNT, "preview should return 1:1");
    }

    function testPreviewDepositWstETH() external {
        uint256 previewShares = sy.previewDeposit(address(wstETH), AMOUNT);
        assertEq(previewShares, AMOUNT, "wstETH preview should be 1:1");
    }

    function testPreviewRedeemSTETH() external {
        uint256 previewAmount = sy.previewRedeem(address(stETH), AMOUNT);
        assertEq(previewAmount, AMOUNT, "preview should return 1:1");
    }

    function testPreviewRedeemWstETH() external {
        uint256 previewAmount = sy.previewRedeem(address(wstETH), AMOUNT);
        assertEq(previewAmount, AMOUNT, "wstETH preview should be 1:1");
    }

    function testDepositZeroReverts() external {
        vm.prank(USER);
        vm.expectRevert(IStandardizedYield.SYZeroDeposit.selector);
        sy.deposit{value: 0}(USER, address(0), 0, 0);
    }

    function testRedeemZeroReverts() external {
        vm.prank(USER);
        vm.expectRevert(IStandardizedYield.SYZeroRedeem.selector);
        sy.redeem(USER, 0, address(stETH), 0, false);
    }

    // ============================================
    // Fuzz tests
    // ============================================

    /**
     * @dev Fuzz native ETH deposit across varying amounts.
     */
    function testFuzz_NativeDepositAtVaryingRates(uint256 ethAmount) external {
        ethAmount = bound(ethAmount, 1, 1000 ether);

        vm.deal(USER, ethAmount);
        vm.prank(USER);
        uint256 sharesOut = sy.deposit{value: ethAmount}(USER, address(0), ethAmount, 0);

        assertEq(sharesOut, ethAmount);
        assertEq(sy.balanceOf(USER), ethAmount);
    }

    /**
     * @dev Fuzz stETH deposit across varying amounts via the submit path.
     */
    function testFuzz_StETHDepositAtVaryingStEthPerToken(uint256 stETHAmount) external {
        stETHAmount = bound(stETHAmount, 1, 1000 ether);

        // Give USER native ETH so stETH.submit (payable) can mint
        vm.deal(USER, stETHAmount);
        vm.prank(USER);
        stETH.submit{value: stETHAmount}(address(0));

        vm.prank(USER);
        stETH.approve(address(sy), stETHAmount);
        vm.prank(USER);
        uint256 sharesOut = sy.deposit(USER, address(stETH), stETHAmount, 0);

        assertEq(sharesOut, stETHAmount);
        assertEq(sy.balanceOf(USER), stETHAmount);
    }
}
