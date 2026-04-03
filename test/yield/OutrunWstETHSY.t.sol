// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {OutrunERC20} from "../../src/assets/base/OutrunERC20.sol";
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
}
