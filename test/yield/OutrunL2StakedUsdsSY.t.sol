// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {OutrunERC20} from "../../src/assets/base/OutrunERC20.sol";
import {IStandardizedYield} from "../../src/yield/interfaces/IStandardizedYield.sol";
import {OutrunL2StakedUsdsSY} from "../../src/yield/adapters/sky/OutrunL2StakedUsdsSY.sol";

contract MockERC20 is OutrunERC20 {
    constructor(string memory name, string memory symbol) OutrunERC20(name, symbol, 18) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockPSM3 {
    // Track swap calls for verification
    address public lastAssetIn;
    address public lastAssetOut;
    uint256 public lastAmountIn;
    address public lastReceiver;

    // Preview rate for sUSDS -> USDS (used for exchangeRate)
    uint256 public sUsdsToUsdsRate = 1.05e18;

    function setSUsdsToUsdsRate(uint256 rate) external {
        sUsdsToUsdsRate = rate;
    }

    function swapExactIn(address assetIn, address assetOut, uint256 amountIn, uint256, address receiver, uint256)
        external
        returns (uint256 amountOut)
    {
        // Record call details
        lastAssetIn = assetIn;
        lastAssetOut = assetOut;
        lastAmountIn = amountIn;
        lastReceiver = receiver;

        // 1:1 swap for simplicity in mock
        amountOut = amountIn;

        // Transfer from caller to this contract
        MockERC20(assetIn).transferFrom(msg.sender, address(this), amountIn);
        // Mint to receiver (simulating swap output)
        MockERC20(assetOut).mint(receiver, amountOut);
    }

    function previewSwapExactIn(address, address, uint256 amountIn) external pure returns (uint256) {
        // 1:1 preview for all pairs in mock
        return amountIn;
    }
}

contract MockPSM3Reverting {
    function swapExactIn(address, address, uint256, uint256, address, uint256) external pure returns (uint256) {
        revert("PSM3 paused");
    }

    function previewSwapExactIn(address, address, uint256) external pure returns (uint256) {
        return 0;
    }
}

contract OutrunL2StakedUsdsSYTest is Test {
    address internal constant OWNER = address(0xA11CE);
    address internal constant USER = address(0xB0B);

    uint256 internal constant AMOUNT = 5 ether;

    MockERC20 internal usdc;
    MockERC20 internal usds;
    MockERC20 internal sUSDS;
    MockPSM3 internal psm3;
    OutrunL2StakedUsdsSY internal sy;

    function setUp() external {
        usdc = new MockERC20("USD Coin", "USDC");
        usds = new MockERC20("Sky Savings Token", "USDS");
        sUSDS = new MockERC20("Sky Savings sUSDS", "sUSDS");
        psm3 = new MockPSM3();

        sy = new OutrunL2StakedUsdsSY(OWNER, address(usdc), address(usds), address(sUSDS), address(psm3));

        // Mint tokens to user
        usdc.mint(USER, AMOUNT * 10);
        usds.mint(USER, AMOUNT * 10);
        sUSDS.mint(USER, AMOUNT * 10);
    }

    // ============================================
    // Deposit paths
    // ============================================

    function testDepositSUSDSPassthrough() external {
        uint256 syBalanceBefore = sy.balanceOf(USER);
        uint256 sUSDSBalanceBefore = sUSDS.balanceOf(USER);

        vm.prank(USER);
        sUSDS.approve(address(sy), AMOUNT);

        vm.prank(USER);
        uint256 sharesOut = sy.deposit(USER, address(sUSDS), AMOUNT, 0);

        // Verify 1:1 passthrough
        assertEq(sharesOut, AMOUNT, "sharesOut should equal AMOUNT (1:1 passthrough)");
        assertEq(sy.balanceOf(USER), syBalanceBefore + AMOUNT, "SY balance should increase");
        assertEq(sUSDS.balanceOf(USER), sUSDSBalanceBefore - AMOUNT, "sUSDS should be transferred out");
    }

    function testDepositUSDCSwapsViaPSM3() external {
        uint256 syBalanceBefore = sy.balanceOf(USER);
        uint256 usdcBalanceBefore = usdc.balanceOf(USER);

        vm.prank(USER);
        usdc.approve(address(sy), AMOUNT);

        vm.prank(USER);
        uint256 sharesOut = sy.deposit(USER, address(usdc), AMOUNT, 0);

        // Verify PSM3 swap called
        assertEq(psm3.lastAssetIn(), address(usdc), "PSM3 should receive USDC");
        assertEq(psm3.lastAssetOut(), address(sUSDS), "PSM3 should output sUSDS");
        assertEq(psm3.lastAmountIn(), AMOUNT, "PSM3 should receive correct amount");
        assertEq(psm3.lastReceiver(), address(sy), "PSM3 should send to SY contract");

        // Verify shares minted
        assertEq(sharesOut, AMOUNT, "sharesOut should equal AMOUNT");
        assertEq(sy.balanceOf(USER), syBalanceBefore + AMOUNT, "SY balance should increase");
        assertEq(usdc.balanceOf(USER), usdcBalanceBefore - AMOUNT, "USDC should be transferred out");
    }

    function testDepositUSDSSwapsViaPSM3() external {
        uint256 syBalanceBefore = sy.balanceOf(USER);
        uint256 usdsBalanceBefore = usds.balanceOf(USER);

        vm.prank(USER);
        usds.approve(address(sy), AMOUNT);

        vm.prank(USER);
        uint256 sharesOut = sy.deposit(USER, address(usds), AMOUNT, 0);

        // Verify PSM3 swap called
        assertEq(psm3.lastAssetIn(), address(usds), "PSM3 should receive USDS");
        assertEq(psm3.lastAssetOut(), address(sUSDS), "PSM3 should output sUSDS");
        assertEq(psm3.lastAmountIn(), AMOUNT, "PSM3 should receive correct amount");

        // Verify shares minted
        assertEq(sharesOut, AMOUNT, "sharesOut should equal AMOUNT");
        assertEq(sy.balanceOf(USER), syBalanceBefore + AMOUNT, "SY balance should increase");
        assertEq(usds.balanceOf(USER), usdsBalanceBefore - AMOUNT, "USDS should be transferred out");
    }

    // ============================================
    // Redeem paths
    // ============================================

    function testRedeemToSUSDS() external {
        // First deposit to get SY shares
        vm.prank(USER);
        sUSDS.approve(address(sy), AMOUNT);
        vm.prank(USER);
        uint256 sharesOut = sy.deposit(USER, address(sUSDS), AMOUNT, 0);

        uint256 sUSDSBalanceBefore = sUSDS.balanceOf(USER);

        vm.prank(USER);
        uint256 amountOut = sy.redeem(USER, sharesOut, address(sUSDS), 0, false);

        // Verify direct transfer
        assertEq(amountOut, sharesOut, "amountOut should equal shares redeemed");
        assertEq(sUSDS.balanceOf(USER), sUSDSBalanceBefore + sharesOut, "sUSDS should be received");
        assertEq(sy.balanceOf(USER), 0, "SY shares should be burned");
    }

    function testRedeemToUSDCSwapsViaPSM3() external {
        // First deposit to get SY shares
        vm.prank(USER);
        sUSDS.approve(address(sy), AMOUNT);
        vm.prank(USER);
        uint256 sharesOut = sy.deposit(USER, address(sUSDS), AMOUNT, 0);

        uint256 usdcBalanceBefore = usdc.balanceOf(USER);

        vm.prank(USER);
        uint256 amountOut = sy.redeem(USER, sharesOut, address(usdc), 0, false);

        // Verify PSM3 swap called for redemption
        assertEq(psm3.lastAssetIn(), address(sUSDS), "PSM3 should receive sUSDS for swap");
        assertEq(psm3.lastAssetOut(), address(usdc), "PSM3 should output USDC");
        assertEq(psm3.lastAmountIn(), sharesOut, "PSM3 should receive shares amount");
        assertEq(psm3.lastReceiver(), USER, "PSM3 should send to user");

        // Verify output
        assertEq(amountOut, sharesOut, "amountOut should equal shares redeemed");
        assertEq(usdc.balanceOf(USER), usdcBalanceBefore + sharesOut, "USDC should be received");
        assertEq(sy.balanceOf(USER), 0, "SY shares should be burned");
    }

    function testRedeemToUSDSSwapsViaPSM3() external {
        // First deposit to get SY shares
        vm.prank(USER);
        sUSDS.approve(address(sy), AMOUNT);
        vm.prank(USER);
        uint256 sharesOut = sy.deposit(USER, address(sUSDS), AMOUNT, 0);

        uint256 usdsBalanceBefore = usds.balanceOf(USER);

        vm.prank(USER);
        uint256 amountOut = sy.redeem(USER, sharesOut, address(usds), 0, false);

        // Verify PSM3 swap called for redemption
        assertEq(psm3.lastAssetIn(), address(sUSDS), "PSM3 should receive sUSDS for swap");
        assertEq(psm3.lastAssetOut(), address(usds), "PSM3 should output USDS");

        // Verify output
        assertEq(amountOut, sharesOut, "amountOut should equal shares redeemed");
        assertEq(usds.balanceOf(USER), usdsBalanceBefore + sharesOut, "USDS should be received");
        assertEq(sy.balanceOf(USER), 0, "SY shares should be burned");
    }

    // ============================================
    // Exchange rate
    // ============================================

    function testExchangeRateReadsPSM3Preview() external {
        // exchangeRate calls PSM3.previewSwapExactIn(sUSDS, USDS, 1 ether)
        uint256 rate = sy.exchangeRate();
        // Our mock returns 1:1, so rate should be 1e18
        assertEq(rate, 1e18, "exchangeRate should return PSM3 preview for 1 sUSDS -> USDS");
    }

    function testDepositUSDCSlippageReverts() external {
        vm.prank(USER);
        usdc.approve(address(sy), AMOUNT);

        uint256 slippageMinShares = AMOUNT + 1;
        vm.prank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(IStandardizedYield.SYInsufficientSharesOut.selector, AMOUNT, slippageMinShares)
        );
        sy.deposit(USER, address(usdc), AMOUNT, slippageMinShares);
    }

    function testRedeemToUSDCSlippageReverts() external {
        vm.prank(USER);
        sUSDS.approve(address(sy), AMOUNT);
        vm.prank(USER);
        sy.deposit(USER, address(sUSDS), AMOUNT, 0);

        uint256 minTokenOut = AMOUNT + 1;
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(IStandardizedYield.SYInsufficientTokenOut.selector, AMOUNT, minTokenOut));
        sy.redeem(USER, AMOUNT, address(usdc), minTokenOut, false);
    }

    function testDepositSUSDSSlippageReverts() external {
        vm.prank(USER);
        sUSDS.approve(address(sy), AMOUNT);

        uint256 slippageMinShares = AMOUNT + 1;
        vm.prank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(IStandardizedYield.SYInsufficientSharesOut.selector, AMOUNT, slippageMinShares)
        );
        sy.deposit(USER, address(sUSDS), AMOUNT, slippageMinShares);
    }

    function testDepositZeroReverts() external {
        vm.prank(USER);
        sUSDS.approve(address(sy), 1 ether);
        vm.expectRevert(IStandardizedYield.SYZeroDeposit.selector);
        sy.deposit(USER, address(sUSDS), 0, 0);
    }

    function testRedeemZeroReverts() external {
        vm.prank(USER);
        vm.expectRevert(IStandardizedYield.SYZeroRedeem.selector);
        sy.redeem(USER, 0, address(sUSDS), 0, false);
    }

    function testPSM3SwapFailurePath() external {
        MockPSM3Reverting revertingPSM3 = new MockPSM3Reverting();
        usdc.mint(USER, AMOUNT);

        OutrunL2StakedUsdsSY syBroken =
            new OutrunL2StakedUsdsSY(OWNER, address(usdc), address(usds), address(sUSDS), address(revertingPSM3));

        vm.prank(USER);
        usdc.approve(address(syBroken), AMOUNT);

        vm.prank(USER);
        vm.expectRevert();
        syBroken.deposit(USER, address(usdc), AMOUNT, 0);
    }
}
