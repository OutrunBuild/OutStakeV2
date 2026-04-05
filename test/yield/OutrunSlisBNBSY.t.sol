// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {OutrunERC20} from "../../src/assets/base/OutrunERC20.sol";
import {NativeAmountMismatch} from "../../src/libraries/CommonErrors.sol";
import {IStandardizedYield} from "../../src/yield/interfaces/IStandardizedYield.sol";
import {IListaBNBStakeManager} from "../../src/integrations/lista/interfaces/IListaBNBStakeManager.sol";
import {ISlisBNBProvider} from "../../src/integrations/lista/interfaces/ISlisBNBProvider.sol";
import {OutrunSlisBNBSY} from "../../src/yield/adapters/lista/OutrunSlisBNBSY.sol";

contract MockSlisBNB is OutrunERC20 {
    constructor() OutrunERC20("Lista Liquid Staked BNB", "slisBNB", 18) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockListaBNBStakeManager is IListaBNBStakeManager {
    MockSlisBNB public slisBNB;
    uint256 public bnbToSnBnbRate = 1e18; // 1 BNB = 1 slisBNB by default
    uint256 public snBnbToBnbRate = 1e18; // 1 slisBNB = 1 BNB by default
    uint256 public lastDepositValue;

    constructor(address _slisBNB) {
        slisBNB = MockSlisBNB(_slisBNB);
    }

    function setBnbToSnBnbRate(uint256 rate) external {
        bnbToSnBnbRate = rate;
    }

    function setSnBnbToBnbRate(uint256 rate) external {
        snBnbToBnbRate = rate;
    }

    function deposit() external payable override {
        lastDepositValue = msg.value;
        // Mint slisBNB to caller (simulating Lista stake behavior)
        uint256 slisBnbAmount = (msg.value * bnbToSnBnbRate) / 1e18;
        slisBNB.mint(msg.sender, slisBnbAmount);
    }

    function convertBnbToSnBnb(uint256 _amount) external view override returns (uint256) {
        return (_amount * bnbToSnBnbRate) / 1e18;
    }

    function convertSnBnbToBnb(uint256 _amountInSlisBnb) external view override returns (uint256) {
        return (_amountInSlisBnb * snBnbToBnbRate) / 1e18;
    }

    function lastDepositAmount() external view returns (uint256) {
        return lastDepositValue;
    }
}

contract MockSlisBNBProvider is ISlisBNBProvider {
    MockSlisBNB public slisBNB;
    address public lastDelegateTo;
    uint256 public lastProvideAmount;
    address public lastReleaseRecipient;
    uint256 public lastReleaseAmount;

    constructor(address _slisBNB) {
        slisBNB = MockSlisBNB(_slisBNB);
    }

    function provide(uint256 amount, address delegateTo) external override returns (uint256) {
        lastProvideAmount = amount;
        lastDelegateTo = delegateTo;
        // Pull slisBNB from caller
        slisBNB.transferFrom(msg.sender, address(this), amount);
        return amount;
    }

    function release(address recipient, uint256 amount) external override returns (uint256) {
        lastReleaseRecipient = recipient;
        lastReleaseAmount = amount;
        // Transfer slisBNB to recipient
        slisBNB.transfer(recipient, amount);
        return amount;
    }
}

contract OutrunSlisBNBSYTest is Test {
    address internal constant OWNER = address(0xA11CE);
    address internal constant USER = address(0xB0B);
    address internal constant DELEGATE_TO = address(0xD313373);

    uint256 internal constant AMOUNT = 5 ether;

    MockSlisBNB internal slisBNB;
    MockListaBNBStakeManager internal stakeManager;
    MockSlisBNBProvider internal provider;
    OutrunSlisBNBSY internal sy;

    function setUp() external {
        slisBNB = new MockSlisBNB();
        stakeManager = new MockListaBNBStakeManager(address(slisBNB));
        provider = new MockSlisBNBProvider(address(slisBNB));

        sy = new OutrunSlisBNBSY(
            OWNER,
            address(slisBNB),
            DELEGATE_TO,
            IListaBNBStakeManager(address(stakeManager)),
            ISlisBNBProvider(address(provider))
        );

        // Mint slisBNB to user
        slisBNB.mint(USER, AMOUNT * 10);
        vm.deal(USER, AMOUNT * 10);
    }

    // ============================================
    // Deposit paths
    // ============================================

    function testDepositNATIVEConvertsAndProvides() external {
        uint256 syBalanceBefore = sy.balanceOf(USER);
        uint256 nativeBalanceBefore = USER.balance;

        vm.prank(USER);
        uint256 sharesOut = sy.deposit{value: AMOUNT}(USER, address(0), AMOUNT, 0);

        // Verify stakeManager.deposit was called with BNB
        assertEq(stakeManager.lastDepositAmount(), AMOUNT, "stakeManager should receive BNB");

        // Verify provider.provide was called
        assertEq(provider.lastProvideAmount(), AMOUNT, "provider should receive slisBNB amount");
        assertEq(provider.lastDelegateTo(), DELEGATE_TO, "provider should use correct delegateTo");

        // Verify shares minted
        assertEq(sharesOut, AMOUNT, "sharesOut should equal converted slisBNB amount");
        assertEq(sy.balanceOf(USER), syBalanceBefore + AMOUNT, "SY balance should increase");
        assertEq(USER.balance, nativeBalanceBefore - AMOUNT, "Native BNB should be deducted");
    }

    function testDepositSlisBNBPassthrough() external {
        uint256 syBalanceBefore = sy.balanceOf(USER);
        uint256 slisBNBBalanceBefore = slisBNB.balanceOf(USER);

        vm.prank(USER);
        slisBNB.approve(address(sy), AMOUNT);

        vm.prank(USER);
        uint256 sharesOut = sy.deposit(USER, address(slisBNB), AMOUNT, 0);

        // Verify provider.provide was called
        assertEq(provider.lastProvideAmount(), AMOUNT, "provider should receive slisBNB");
        assertEq(provider.lastDelegateTo(), DELEGATE_TO, "provider should use correct delegateTo");

        // Verify shares minted (1:1 for slisBNB input)
        assertEq(sharesOut, AMOUNT, "sharesOut should equal AMOUNT (1:1 for slisBNB)");
        assertEq(sy.balanceOf(USER), syBalanceBefore + AMOUNT, "SY balance should increase");
        assertEq(slisBNB.balanceOf(USER), slisBNBBalanceBefore - AMOUNT, "slisBNB should be transferred out");
    }

    // ============================================
    // Redeem paths
    // ============================================

    function testRedeemReleasesSlisBNB() external {
        // First deposit to get SY shares
        vm.prank(USER);
        slisBNB.approve(address(sy), AMOUNT);
        vm.prank(USER);
        uint256 sharesOut = sy.deposit(USER, address(slisBNB), AMOUNT, 0);

        uint256 slisBNBBalanceBefore = slisBNB.balanceOf(USER);

        vm.prank(USER);
        uint256 amountOut = sy.redeem(USER, sharesOut, address(slisBNB), 0, false);

        // Verify provider.release was called
        assertEq(provider.lastReleaseRecipient(), USER, "provider should release to user");
        assertEq(provider.lastReleaseAmount(), sharesOut, "provider should release correct amount");

        // Verify slisBNB received
        assertEq(amountOut, sharesOut, "amountOut should equal shares redeemed");
        assertEq(slisBNB.balanceOf(USER), slisBNBBalanceBefore + sharesOut, "slisBNB should be received");
        assertEq(sy.balanceOf(USER), 0, "SY shares should be burned");
    }

    // ============================================
    // Exchange rate
    // ============================================

    function testExchangeRateReadsConvertSnBnbToBnb() external {
        uint256 rate = sy.exchangeRate();
        // Default rate is 1e18
        assertEq(rate, 1e18, "exchangeRate should return stakeManager.convertSnBnbToBnb(1 ether)");

        // Update rate
        stakeManager.setSnBnbToBnbRate(1.1e18);
        rate = sy.exchangeRate();
        assertEq(rate, 1.1e18, "exchangeRate should reflect updated rate");
    }

    // ============================================
    // Owner functions
    // ============================================

    function testUpdateDelegateTo() external {
        // First deposit to have some supply
        vm.prank(USER);
        slisBNB.approve(address(sy), AMOUNT);
        vm.prank(USER);
        sy.deposit(USER, address(slisBNB), AMOUNT, 0);

        address newDelegate = address(0x123456);

        vm.prank(OWNER);
        sy.updateDelegateTo(newDelegate);

        assertEq(sy.delegateTo(), newDelegate, "delegateTo should be updated");

        // Verify release and provide were called for migration
        assertEq(provider.lastReleaseRecipient(), address(sy), "release should be called on SY contract");
        assertEq(provider.lastDelegateTo(), newDelegate, "provide should use new delegate");
    }

    function testDepositNATIVEAmountMismatch() external {
        vm.prank(USER);
        vm.expectRevert(NativeAmountMismatch.selector);
        sy.deposit{value: AMOUNT / 2}(USER, address(0), AMOUNT, 0);
    }

    function testDepositNATIVESlippageReverts() external {
        uint256 slippageMinShares = AMOUNT + 1;

        vm.prank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(IStandardizedYield.SYInsufficientSharesOut.selector, AMOUNT, slippageMinShares)
        );
        sy.deposit{value: AMOUNT}(USER, address(0), AMOUNT, slippageMinShares);
    }

    function testExchangeRateReflectsStakeManagerRate() external {
        uint256 rateBefore = sy.exchangeRate();
        stakeManager.setSnBnbToBnbRate(1.1e18);
        uint256 rateAfter = sy.exchangeRate();
        assertTrue(rateAfter > rateBefore, "exchange rate should increase when stake manager rate increases");
    }

    function testUpdateDelegateToRevertsWhenNotOwner() external {
        address newDelegate = address(0x123456);
        vm.prank(USER);
        vm.expectRevert();
        sy.updateDelegateTo(newDelegate);
    }

    // ============================================
    // Fuzz tests
    // ============================================

    /**
     * @dev Fuzz native BNB deposit across varying rates.
     *      Verifies that minted SY shares match the stake manager's BNB-to-slisBNB conversion.
     */
    function testFuzz_NativeDepositRateVariance(uint256 bnbAmount, uint256 rate) external {
        bnbAmount = bound(bnbAmount, 1, 1000 ether);
        rate = bound(rate, 0.5e18, 1.5e18);
        stakeManager.setBnbToSnBnbRate(rate);

        vm.deal(USER, bnbAmount);
        vm.prank(USER);
        uint256 slisBNBShares = stakeManager.convertBnbToSnBnb(bnbAmount);

        vm.prank(USER);
        uint256 sharesOut = sy.deposit{value: bnbAmount}(USER, address(0), bnbAmount, 0);

        assertEq(sharesOut, slisBNBShares, "shares should match BNB to slisBNB conversion");
    }

    /**
     * @dev Fuzz slisBNB redeem across varying rates.
     *      Redeems should be 1:1 for slisBNB regardless of stake manager rate changes.
     */
    function testFuzz_RedeemRateVariance(uint256 depositAmount, uint256 rateBefore, uint256 rateAfter) external {
        depositAmount = bound(depositAmount, 1, 1000 ether);
        rateBefore = bound(rateBefore, 0.9e18, 1.1e18);
        rateAfter = bound(rateAfter, 0.9e18, 1.1e18);

        stakeManager.setSnBnbToBnbRate(rateBefore);
        slisBNB.mint(USER, depositAmount * 10);

        vm.prank(USER);
        slisBNB.approve(address(sy), depositAmount);
        vm.prank(USER);
        uint256 sharesOut = sy.deposit(USER, address(slisBNB), depositAmount, 0);
        assertEq(sharesOut, depositAmount);

        stakeManager.setSnBnbToBnbRate(rateAfter);

        vm.prank(USER);
        uint256 amountOut = sy.redeem(USER, sharesOut, address(slisBNB), 0, false);

        assertEq(amountOut, sharesOut, "slisBNB redeem should be 1:1 regardless of rate changes");
    }
}
