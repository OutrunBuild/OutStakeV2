// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {OutrunERC20} from "../../src/assets/base/OutrunERC20.sol";
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
}

contract OutrunWeETHSYTest is Test {
    address internal constant OWNER = address(0xA11CE);
    address internal constant USER = address(0xB0B);

    uint256 internal constant AMOUNT = 5 ether;

    MockERC20Token internal eETH;
    MockWeETH internal weETH;
    OutrunWeETHSY internal sy;

    function setUp() external {
        eETH = new MockERC20Token("ether.fi ETH", "eETH", 18);
        weETH = new MockWeETH(address(eETH));
        sy = new OutrunWeETHSY(OWNER, address(eETH), address(weETH), address(0xD3D0), address(0x1));

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
}
