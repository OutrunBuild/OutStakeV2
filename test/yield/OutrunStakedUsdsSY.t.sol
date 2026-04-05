// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {OutrunERC20} from "../../src/assets/base/OutrunERC20.sol";
import {IStandardizedYield} from "../../src/yield/interfaces/IStandardizedYield.sol";
import {OutrunStakedUsdsSY} from "../../src/yield/adapters/sky/OutrunStakedUsdsSY.sol";

contract MockUSDS is OutrunERC20 {
    constructor() OutrunERC20("Sky USDS", "USDS", 18) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockERC4626Vault is OutrunERC20, IERC4626 {
    address internal immutable ASSET;
    uint256 internal exchangeRateMultiplier;

    constructor(address asset_, string memory name_, string memory symbol_) OutrunERC20(name_, symbol_, 18) {
        ASSET = asset_;
        exchangeRateMultiplier = 1e18;
    }

    // External mint for test setup - not part of IERC4626
    function mintShares(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setExchangeRateMultiplier(uint256 multiplier) external {
        exchangeRateMultiplier = multiplier;
    }

    function asset() external view returns (address) {
        return ASSET;
    }

    function totalAssets() external view returns (uint256) {
        return totalSupply * exchangeRateMultiplier / 1e18;
    }

    function convertToShares(uint256 assets) public view returns (uint256) {
        return assets * 1e18 / exchangeRateMultiplier;
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        return shares * exchangeRateMultiplier / 1e18;
    }

    function maxDeposit(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function maxMint(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function maxWithdraw(address owner) external view returns (uint256) {
        return convertToAssets(balanceOf(owner));
    }

    function maxRedeem(address owner) external view returns (uint256) {
        return balanceOf(owner);
    }

    function previewDeposit(uint256 assets) external view returns (uint256) {
        return convertToShares(assets);
    }

    function previewMint(uint256 shares) external view returns (uint256) {
        return convertToAssets(shares);
    }

    function previewWithdraw(uint256 assets) external view returns (uint256) {
        return convertToShares(assets);
    }

    function previewRedeem(uint256 shares) external view returns (uint256) {
        return convertToAssets(shares);
    }

    function deposit(uint256 assets, address receiver) external returns (uint256) {
        MockUSDS(ASSET).transferFrom(msg.sender, address(this), assets);
        uint256 shares = convertToShares(assets);
        _mint(receiver, shares);
        return shares;
    }

    // IERC4626 mint - mints exact shares, pulls needed assets
    function mint(uint256 shares, address receiver) external returns (uint256) {
        uint256 assets = convertToAssets(shares);
        MockUSDS(ASSET).transferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);
        return assets;
    }

    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256) {
        uint256 shares = convertToShares(assets);
        _spendAllowance(owner, msg.sender, shares);
        _burn(owner, shares);
        MockUSDS(ASSET).transfer(receiver, assets);
        return shares;
    }

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256) {
        // ERC4626: if caller is not owner, check allowance
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }
        uint256 assets = convertToAssets(shares);
        _burn(owner, shares);
        MockUSDS(ASSET).transfer(receiver, assets);
        return assets;
    }
}

contract OutrunStakedUsdsSYTest is Test {
    address internal constant OWNER = address(0xA11CE);
    address internal constant USER = address(0xB0B);

    uint256 internal constant DEPOSIT_AMOUNT = 1000 * 1e18;

    MockUSDS internal usds;
    MockERC4626Vault internal sUSDS;
    OutrunStakedUsdsSY internal sy;

    function setUp() external {
        usds = new MockUSDS();
        sUSDS = new MockERC4626Vault(address(usds), "Sky Staked USDS", "sUSDS");
        sy = new OutrunStakedUsdsSY(OWNER, address(usds), address(sUSDS));

        usds.mint(USER, DEPOSIT_AMOUNT * 2);
        sUSDS.mintShares(USER, DEPOSIT_AMOUNT);

        vm.prank(USER);
        usds.approve(address(sy), type(uint256).max);
        vm.prank(USER);
        sUSDS.approve(address(sy), type(uint256).max);
    }

    // ============================================
    // Deposit paths
    // ============================================

    function testDepositUSDSDepositsIntoVault() external {
        uint256 usdsBalanceBefore = usds.balanceOf(USER);
        uint256 susdsBalanceBefore = sUSDS.balanceOf(address(sy));

        vm.expectCall(address(sUSDS), abi.encodeCall(IERC4626.deposit, (DEPOSIT_AMOUNT, address(sy))));

        vm.prank(USER);
        uint256 sharesOut = sy.deposit(USER, address(usds), DEPOSIT_AMOUNT, 0);

        assertEq(sharesOut, DEPOSIT_AMOUNT, "sharesOut should equal deposit at 1:1 rate");
        assertEq(sy.balanceOf(USER), DEPOSIT_AMOUNT, "SY balance should increase");
        assertEq(usds.balanceOf(USER), usdsBalanceBefore - DEPOSIT_AMOUNT, "USDS should be transferred out");
        assertEq(sUSDS.balanceOf(address(sy)), susdsBalanceBefore + DEPOSIT_AMOUNT, "sUSDS should be in SY");
    }

    function testDepositSUSDSPassthrough() external {
        uint256 susdsBalanceBefore = sUSDS.balanceOf(USER);
        uint256 syBalanceBefore = sy.balanceOf(USER);

        vm.prank(USER);
        uint256 sharesOut = sy.deposit(USER, address(sUSDS), DEPOSIT_AMOUNT, 0);

        assertEq(sharesOut, DEPOSIT_AMOUNT, "sharesOut should equal deposit (1:1 passthrough)");
        assertEq(sy.balanceOf(USER), syBalanceBefore + DEPOSIT_AMOUNT, "SY balance should increase");
        assertEq(sUSDS.balanceOf(USER), susdsBalanceBefore - DEPOSIT_AMOUNT, "sUSDS should be transferred out");
    }

    // ============================================
    // Redeem paths
    // ============================================

    function testRedeemToUSDSRedeemsFromVault() external {
        vm.prank(USER);
        sy.deposit(USER, address(usds), DEPOSIT_AMOUNT, 0);

        uint256 usdsBalanceBefore = usds.balanceOf(USER);

        vm.expectCall(address(sUSDS), abi.encodeCall(IERC4626.redeem, (DEPOSIT_AMOUNT, USER, address(sy))));

        vm.prank(USER);
        uint256 amountOut = sy.redeem(USER, DEPOSIT_AMOUNT, address(usds), 0, false);

        assertEq(amountOut, DEPOSIT_AMOUNT, "amountOut should equal shares redeemed at 1:1 rate");
        assertEq(usds.balanceOf(USER), usdsBalanceBefore + DEPOSIT_AMOUNT, "USDS should be received");
        assertEq(sy.balanceOf(USER), 0, "SY shares should be burned");
    }

    function testRedeemToSUSDSPassthrough() external {
        vm.prank(USER);
        sy.deposit(USER, address(usds), DEPOSIT_AMOUNT, 0);

        uint256 susdsBalanceBefore = sUSDS.balanceOf(USER);

        vm.prank(USER);
        uint256 amountOut = sy.redeem(USER, DEPOSIT_AMOUNT, address(sUSDS), 0, false);

        assertEq(amountOut, DEPOSIT_AMOUNT, "amountOut should equal shares (1:1 passthrough)");
        assertEq(sUSDS.balanceOf(USER), susdsBalanceBefore + DEPOSIT_AMOUNT, "sUSDS should be received");
        assertEq(sy.balanceOf(USER), 0, "SY shares should be burned");
    }

    // ============================================
    // Exchange rate
    // ============================================

    function testExchangeRateReadsVaultConvertToAssets() external {
        uint256 rate = sy.exchangeRate();
        assertEq(rate, 1e18, "exchangeRate should be 1e18 at initial 1:1 rate");

        sUSDS.setExchangeRateMultiplier(2e18);
        rate = sy.exchangeRate();
        assertEq(rate, 2e18, "exchangeRate should reflect vault rate change");
    }

    function testDepositUSDSSlippageReverts() external {
        uint256 slippageMinShares = DEPOSIT_AMOUNT + 1;

        vm.prank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(
                IStandardizedYield.SYInsufficientSharesOut.selector, DEPOSIT_AMOUNT, slippageMinShares
            )
        );
        sy.deposit(USER, address(usds), DEPOSIT_AMOUNT, slippageMinShares);
    }

    function testRedeemToUSDSSlippageReverts() external {
        vm.prank(USER);
        sy.deposit(USER, address(usds), DEPOSIT_AMOUNT, 0);

        uint256 minTokenOut = DEPOSIT_AMOUNT + 1;
        vm.prank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(IStandardizedYield.SYInsufficientTokenOut.selector, DEPOSIT_AMOUNT, minTokenOut)
        );
        sy.redeem(USER, DEPOSIT_AMOUNT, address(usds), minTokenOut, false);
    }

    function testExchangeRateReflectsVaultGrowth() external {
        sUSDS.setExchangeRateMultiplier(1.2e18);

        uint256 rateAfter = sy.exchangeRate();
        assertTrue(rateAfter > 1e18, "exchange rate should increase as vault accrues yield");
    }
}
