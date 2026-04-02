// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {SYBase} from "../../src/yield/SYBase.sol";
import {OutrunERC20} from "../../src/assets/base/OutrunERC20.sol";
import {IStandardizedYield} from "../../src/yield/interfaces/IStandardizedYield.sol";

contract MockSYBaseToken is OutrunERC20 {
    constructor() OutrunERC20("Mock Asset", "mAST", 18) {}

    function mint(address receiver, uint256 amount) external {
        _mint(receiver, amount);
    }
}

contract MockSYBase is SYBase {
    address internal immutable token;

    constructor(address owner_, address token_) SYBase("Mock SY", "mSY", token_, owner_) {
        token = token_;
    }

    function _deposit(address, uint256 amountDeposited) internal pure override returns (uint256 amountSharesOut) {
        return amountDeposited;
    }

    function _redeem(address receiver, address tokenOut, uint256 amountSharesToRedeem)
        internal
        virtual
        override
        returns (uint256 amountTokenOut)
    {
        amountTokenOut = amountSharesToRedeem;
        _transferOut(tokenOut, receiver, amountTokenOut);
    }

    function exchangeRate() external pure override returns (uint256 res) {
        return 1e18;
    }

    function _previewDeposit(address, uint256 amountTokenToDeposit)
        internal
        pure
        override
        returns (uint256 amountSharesOut)
    {
        return amountTokenToDeposit;
    }

    function _previewRedeem(address, uint256 amountSharesToRedeem)
        internal
        pure
        override
        returns (uint256 amountTokenOut)
    {
        return amountSharesToRedeem;
    }

    function getTokensIn() public view override returns (address[] memory res) {
        res = new address[](2);
        res[0] = token;
        res[1] = NATIVE;
    }

    function getTokensOut() public view override returns (address[] memory res) {
        res = new address[](2);
        res[0] = token;
        res[1] = NATIVE;
    }

    function isValidTokenIn(address tokenIn) public view override returns (bool) {
        return tokenIn == token || tokenIn == NATIVE;
    }

    function isValidTokenOut(address tokenOut) public view override returns (bool) {
        return tokenOut == token || tokenOut == NATIVE;
    }

    function exposedTransferIn(address tokenIn, address from, uint256 amount) external payable {
        _transferIn(tokenIn, from, amount);
    }

    function assetInfo()
        external
        view
        override
        returns (IStandardizedYield.AssetType assetType, address assetAddress, uint8 assetDecimals)
    {
        return (IStandardizedYield.AssetType.TOKEN, token, 18);
    }
}

contract LegacyLockedMockSYBase is MockSYBase {
    constructor(address owner_, address token_) MockSYBase(owner_, token_) {}

    function _redeem(address receiver, address tokenOut, uint256 amountSharesToRedeem)
        internal
        override
        returns (uint256 amountTokenOut)
    {
        amountTokenOut = amountSharesToRedeem;
        _transferOutWithLegacyLock(tokenOut, receiver, amountTokenOut);
    }

    function _transferOutWithLegacyLock(address tokenOut, address receiver, uint256 amount) internal nonReentrant {
        _transferOut(tokenOut, receiver, amount);
    }
}

contract ReentrantRedeemReceiver {
    bytes4 internal constant REENTRANCY_GUARD_REENTRANT_CALL_SELECTOR =
        bytes4(keccak256("ReentrancyGuardReentrantCall()"));

    IStandardizedYield internal immutable sy;

    uint256 internal reentryShares;
    bool internal reentryAttempted;
    bool internal reentryBlockedByGuard;
    bool internal reentrySucceededUnexpectedly;

    constructor(IStandardizedYield sy_) {
        sy = sy_;
    }

    // solhint-disable-next-line no-complex-fallback
    receive() external payable {
        uint256 sharesToReenter = reentryShares;
        if (sharesToReenter == 0) return;

        reentryAttempted = true;
        reentryShares = 0;

        try sy.redeem(address(this), sharesToReenter, address(0), 0, false) returns (uint256) {
            reentrySucceededUnexpectedly = true;
        } catch (bytes memory reason) {
            reentryBlockedByGuard =
                keccak256(reason) == keccak256(abi.encodeWithSelector(REENTRANCY_GUARD_REENTRANT_CALL_SELECTOR));
        }
    }

    function depositNative() external payable returns (uint256 amountSharesOut) {
        amountSharesOut = sy.deposit{value: msg.value}(address(this), address(0), msg.value, 0);
    }

    function attackRedeem(uint256 outerShares, uint256 innerShares) external returns (uint256 amountTokenOut) {
        reentryAttempted = false;
        reentryBlockedByGuard = false;
        reentrySucceededUnexpectedly = false;
        reentryShares = innerShares;

        amountTokenOut = sy.redeem(address(this), outerShares, address(0), 0, false);
    }

    function attemptedReentry() external view returns (bool) {
        return reentryAttempted;
    }

    function reentryBlocked() external view returns (bool) {
        return reentryBlockedByGuard;
    }

    function reentrySucceeded() external view returns (bool) {
        return reentrySucceededUnexpectedly;
    }
}

contract SYBaseDepositGuardTest is Test {
    bytes4 internal constant NATIVE_AMOUNT_MISMATCH_SELECTOR = bytes4(keccak256("NativeAmountMismatch()"));
    bytes4 internal constant REENTRANCY_GUARD_REENTRANT_CALL_SELECTOR =
        bytes4(keccak256("ReentrancyGuardReentrantCall()"));
    uint256 internal constant AMOUNT = 1e18;

    MockSYBaseToken internal underlying;
    MockSYBase internal sy;
    LegacyLockedMockSYBase internal legacySy;

    address internal owner = address(0xA11CE);
    address internal user = address(0xBEEF);

    function setUp() external {
        underlying = new MockSYBaseToken();
        sy = new MockSYBase(owner, address(underlying));
        legacySy = new LegacyLockedMockSYBase(owner, address(underlying));

        underlying.mint(user, AMOUNT * 2);
        vm.deal(user, AMOUNT * 2);
        vm.deal(address(this), AMOUNT * 4);

        vm.prank(user);
        underlying.approve(address(sy), type(uint256).max);
    }

    function testDepositRevertsWhenERC20InputCarriesMsgValue() external {
        vm.prank(user);
        vm.expectRevert(NATIVE_AMOUNT_MISMATCH_SELECTOR);
        sy.deposit{value: 1}(user, address(underlying), AMOUNT, 0);
    }

    function testTransferInRevertsWhenERC20InputCarriesMsgValue() external {
        vm.prank(user);
        vm.expectRevert(NATIVE_AMOUNT_MISMATCH_SELECTOR);
        sy.exposedTransferIn{value: 1}(address(underlying), user, AMOUNT);
    }

    function testDepositAcceptsNativeInputWithMatchingMsgValue() external {
        vm.prank(user);
        uint256 sharesOut = sy.deposit{value: AMOUNT}(user, address(0), AMOUNT, 0);

        assertEq(sharesOut, AMOUNT);
        assertEq(sy.balanceOf(user), AMOUNT);
        assertEq(address(sy).balance, AMOUNT);
    }

    function testRedeemTransfersOutWithoutNestedReentrancyRevert() external {
        vm.startPrank(user);
        sy.deposit(user, address(underlying), AMOUNT, 0);

        uint256 amountTokenOut = sy.redeem(user, AMOUNT, address(underlying), 0, false);
        vm.stopPrank();

        assertEq(amountTokenOut, AMOUNT);
        assertEq(sy.balanceOf(user), 0);
        assertEq(underlying.balanceOf(user), AMOUNT * 2);
        assertEq(underlying.balanceOf(address(sy)), 0);
    }

    function testLegacyLockedTransferOutWouldStillSelfCollide() external {
        ReentrantRedeemReceiver attacker = new ReentrantRedeemReceiver(IStandardizedYield(address(legacySy)));
        attacker.depositNative{value: AMOUNT}();

        vm.expectRevert(REENTRANCY_GUARD_REENTRANT_CALL_SELECTOR);
        attacker.attackRedeem(AMOUNT, AMOUNT);

        assertFalse(attacker.attemptedReentry());
        assertEq(legacySy.balanceOf(address(attacker)), AMOUNT);
        assertEq(address(legacySy).balance, AMOUNT);
        assertEq(address(attacker).balance, 0);
    }

    function testRedeemNativeBlocksCallbackReentryWhileOuterRedeemSucceeds() external {
        ReentrantRedeemReceiver attacker = new ReentrantRedeemReceiver(IStandardizedYield(address(sy)));
        attacker.depositNative{value: AMOUNT * 2}();

        uint256 amountTokenOut = attacker.attackRedeem(AMOUNT, AMOUNT);

        assertEq(amountTokenOut, AMOUNT);
        assertTrue(attacker.attemptedReentry());
        assertTrue(attacker.reentryBlocked());
        assertFalse(attacker.reentrySucceeded());
        assertEq(sy.balanceOf(address(attacker)), AMOUNT);
        assertEq(address(sy).balance, AMOUNT);
        assertEq(address(attacker).balance, AMOUNT);
    }
}
