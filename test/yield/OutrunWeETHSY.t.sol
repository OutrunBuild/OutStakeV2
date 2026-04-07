// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {OutrunERC20} from "../../src/assets/base/OutrunERC20.sol";
import {IStandardizedYield} from "../../src/yield/interfaces/IStandardizedYield.sol";
import {OutrunWeETHSY} from "../../src/yield/adapters/etherfi/OutrunWeETHSY.sol";

contract MockERC20Token is OutrunERC20 {
    constructor(string memory name_, string memory symbol_, uint8 decimals_) OutrunERC20(name_, symbol_, decimals_) {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }
}

contract MockWeETH is OutrunERC20 {
    error MockWrapTransferFailed();
    error MockUnwrapTransferFailed();

    MockERC20Token internal immutable eETH;

    constructor(address eETH_) OutrunERC20("Wrapped eETH", "weETH", 18) {
        eETH = MockERC20Token(eETH_);
    }

    function wrap(uint256 eETHAmount) external returns (uint256 weETHAmount) {
        if (!eETH.transferFrom(msg.sender, address(this), eETHAmount)) revert MockWrapTransferFailed();
        _mint(msg.sender, eETHAmount);
        return eETHAmount;
    }

    function unwrap(uint256 weETHAmount) external returns (uint256 eETHAmount) {
        _burn(msg.sender, weETHAmount);
        if (!eETH.transfer(msg.sender, weETHAmount)) revert MockUnwrapTransferFailed();
        return weETHAmount;
    }

    function mintTo(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// Mock liquidity pool that implements ILiquidityPool + IDepositAdapter
contract MockLiquidityPool {
    uint256 internal rate = 1 ether;
    MockWeETH internal immutable weETH;

    constructor(MockWeETH weETH_) {
        weETH = weETH_;
    }

    function setRate(uint256 newRate) external {
        rate = newRate;
    }

    // ILiquidityPool
    function sharesForAmount(uint256 amount) external view returns (uint256) {
        return amount * 1 ether / rate;
    }

    function amountForShare(uint256 shares) external view returns (uint256) {
        return shares * rate / 1 ether;
    }

    // IDepositAdapter
    function depositETHForWeETH(address) external payable returns (uint256) {
        uint256 shares = msg.value * 1 ether / rate;
        weETH.mintTo(msg.sender, shares);
        return shares;
    }
}

contract OutrunWeETHSYTest is Test {
    address internal constant OWNER = address(0xA11CE);
    address internal constant USER = address(0xB0B);

    uint256 internal constant AMOUNT = 5 ether;
    uint256 internal constant TEST_RATE = 1.1 ether;

    MockERC20Token internal eETH;
    MockWeETH internal weETH;

    // Mock liquidity pool that mimics etherfi's wrap rate
    MockLiquidityPool internal liquidityPool;

    OutrunWeETHSY internal sy;

    function setUp() external {
        eETH = new MockERC20Token("ether.fi ETH", "eETH", 18);
        weETH = new MockWeETH(address(eETH));

        liquidityPool = new MockLiquidityPool(weETH);

        sy = new OutrunWeETHSY(OWNER, address(eETH), address(weETH), address(liquidityPool), address(liquidityPool));

        eETH.mint(USER, AMOUNT);
    }

    function testDepositEETHApprovesAndWrapsSuccessfully() external {
        vm.startPrank(USER);
        eETH.approve(address(sy), type(uint256).max);

        uint256 sharesOut = sy.deposit(USER, address(eETH), AMOUNT, 0);

        vm.stopPrank();

        assertEq(sharesOut, AMOUNT);
        assertEq(sy.balanceOf(USER), AMOUNT);
        assertEq(eETH.balanceOf(address(sy)), 0);
        assertEq(eETH.balanceOf(address(weETH)), AMOUNT);
        assertEq(weETH.balanceOf(address(sy)), AMOUNT);
        assertGt(eETH.allowance(address(sy), address(weETH)), 0);
    }

    function testDepositNATIVESlippageReverts() external {
        uint256 ethAmount = 1 ether;
        liquidityPool.setRate(1 ether);

        uint256 expectedShares = liquidityPool.sharesForAmount(ethAmount);
        uint256 slippageMinShares = expectedShares + 1;

        vm.deal(USER, ethAmount);
        vm.prank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(
                IStandardizedYield.SYInsufficientSharesOut.selector, expectedShares, slippageMinShares
            )
        );
        sy.deposit{value: ethAmount}(USER, address(0), ethAmount, slippageMinShares);
    }

    function testDepositNATIVEPassthrough() external {
        uint256 ethAmount = 1 ether;
        liquidityPool.setRate(1 ether);

        vm.deal(USER, ethAmount);
        vm.prank(USER);
        uint256 sharesOut = sy.deposit{value: ethAmount}(USER, address(0), ethAmount, 0);

        assertEq(sharesOut, ethAmount, "NATIVE deposit should return shares from deposit adapter");
        assertEq(weETH.balanceOf(address(sy)), ethAmount, "SY should hold weETH");
    }

    function testDepositWeETHPassthrough() external {
        // Mint weETH to USER by wrapping eETH
        eETH.mint(USER, AMOUNT);
        vm.startPrank(USER);
        eETH.approve(address(weETH), AMOUNT);
        weETH.wrap(AMOUNT);

        weETH.balanceOf(USER);
        weETH.approve(address(sy), AMOUNT);
        uint256 sharesOut = sy.deposit(USER, address(weETH), AMOUNT, 0);
        vm.stopPrank();

        assertEq(sharesOut, AMOUNT, "weETH deposit should be 1:1 passthrough");
        assertEq(sy.balanceOf(USER), AMOUNT);
    }

    function testRedeemToWeETHPassthrough() external {
        eETH.mint(USER, AMOUNT);
        vm.startPrank(USER);
        eETH.approve(address(weETH), AMOUNT);
        weETH.wrap(AMOUNT);
        weETH.approve(address(sy), AMOUNT);
        uint256 sharesOut = sy.deposit(USER, address(weETH), AMOUNT, 0);

        uint256 weETHBalanceBefore = weETH.balanceOf(USER);
        uint256 amountOut = sy.redeem(USER, sharesOut, address(weETH), 0, false);
        vm.stopPrank();

        assertEq(amountOut, sharesOut, "redeem to weETH should be 1:1");
        assertEq(weETH.balanceOf(USER), weETHBalanceBefore + amountOut);
        assertEq(sy.balanceOf(USER), 0);
    }

    function testExchangeRateReadsLiquidityPool() external {
        liquidityPool.setRate(TEST_RATE);

        uint256 rate = sy.exchangeRate();
        assertEq(rate, TEST_RATE, "exchange rate should match pool rate");
    }

    function testPreviewDepositEETH() external {
        liquidityPool.setRate(1 ether);

        uint256 previewShares = sy.previewDeposit(address(eETH), AMOUNT);
        assertEq(previewShares, AMOUNT, "preview should return 1:1 at rate 1");

        liquidityPool.setRate(1.1e18);
        previewShares = sy.previewDeposit(address(eETH), AMOUNT);
        assertGt(previewShares, 0, "preview should return positive shares at different rate");
    }

    function testPreviewDepositNATIVE() external {
        liquidityPool.setRate(1 ether);

        uint256 previewShares = sy.previewDeposit(address(0), AMOUNT);
        assertEq(previewShares, AMOUNT, "preview should return 1:1 for NATIVE at rate 1");
    }

    function testPreviewDepositWeETH() external {
        uint256 previewShares = sy.previewDeposit(address(weETH), AMOUNT);
        assertEq(previewShares, AMOUNT, "weETH preview should be 1:1");
    }

    function testPreviewRedeemEETH() external {
        liquidityPool.setRate(1.1e18);

        uint256 previewAmount = sy.previewRedeem(address(eETH), AMOUNT);
        assertGt(previewAmount, 0, "preview should return positive eETH amount");
    }

    function testPreviewRedeemWeETH() external {
        uint256 previewAmount = sy.previewRedeem(address(weETH), AMOUNT);
        assertEq(previewAmount, AMOUNT, "weETH preview should be 1:1");
    }

    function testDepositZeroReverts() external {
        vm.prank(USER);
        vm.expectRevert(IStandardizedYield.SYZeroDeposit.selector);
        sy.deposit(USER, address(eETH), 0, 0);
    }
}
