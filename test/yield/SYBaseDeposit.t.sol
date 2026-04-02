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

    function assetInfo()
        external
        view
        override
        returns (IStandardizedYield.AssetType assetType, address assetAddress, uint8 assetDecimals)
    {
        return (IStandardizedYield.AssetType.TOKEN, token, 18);
    }
}

contract SYBaseDepositGuardTest is Test {
    bytes4 internal constant NATIVE_AMOUNT_MISMATCH_SELECTOR = bytes4(keccak256("NativeAmountMismatch()"));
    uint256 internal constant AMOUNT = 1e18;

    MockSYBaseToken internal underlying;
    MockSYBase internal sy;

    address internal owner = address(0xA11CE);
    address internal user = address(0xBEEF);

    function setUp() external {
        underlying = new MockSYBaseToken();
        sy = new MockSYBase(owner, address(underlying));

        underlying.mint(user, AMOUNT * 2);
        vm.deal(user, AMOUNT * 2);

        vm.prank(user);
        underlying.approve(address(sy), type(uint256).max);
    }

    function testDepositRevertsWhenERC20InputCarriesMsgValue() external {
        vm.prank(user);
        vm.expectRevert(NATIVE_AMOUNT_MISMATCH_SELECTOR);
        sy.deposit{value: 1}(user, address(underlying), AMOUNT, 0);
    }

    function testDepositAcceptsNativeInputWithMatchingMsgValue() external {
        vm.prank(user);
        uint256 sharesOut = sy.deposit{value: AMOUNT}(user, address(0), AMOUNT, 0);

        assertEq(sharesOut, AMOUNT);
        assertEq(sy.balanceOf(user), AMOUNT);
        assertEq(address(sy).balance, AMOUNT);
    }
}
