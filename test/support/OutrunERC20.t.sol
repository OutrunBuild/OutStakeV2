// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {OutrunERC20} from "../../src/assets/base/OutrunERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Harness to expose internal functions for testing
contract OutrunERC20Harness is OutrunERC20 {
    constructor() OutrunERC20("Test Token", "TST", 18) {}

    function exposedMint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function exposedBurn(address from, uint256 amount) external {
        _burn(from, amount);
    }

    function exposedApprove(address owner, address spender, uint256 value, bool emitEvent) external {
        _approve(owner, spender, value, emitEvent);
    }

    function exposedSpendAllowance(address owner, address spender, uint256 value) external {
        _spendAllowance(owner, spender, value);
    }
}

contract OutrunERC20Test is Test {
    OutrunERC20Harness internal token;

    address internal owner = address(0xA11CE);
    address internal spender = address(0xB0B);
    address internal recipient = address(0xCAFE);

    function setUp() external {
        token = new OutrunERC20Harness();
    }

    // ============ transfer revert tests ============

    function testTransferRevertsOnZeroAddress() external {
        token.exposedMint(owner, 100 ether);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 100 ether);
    }

    function testTransferRevertsOnInsufficientBalance() external {
        token.exposedMint(owner, 50 ether);

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, 50 ether, 100 ether)
        );
        token.transfer(recipient, 100 ether);
    }

    // ============ approve revert tests ============

    function testApproveRevertsOnZeroOwner() external {
        // When owner is address(0), the _msgSender() in approve will be address(0) if we prank it
        vm.prank(address(0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        token.approve(spender, 100 ether);
    }

    function testApproveRevertsOnZeroSpender() external {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 100 ether);
    }

    // ============ transferFrom tests ============

    function testTransferFromRevertsOnInsufficientAllowance() external {
        token.exposedMint(owner, 100 ether);

        vm.prank(owner);
        token.approve(spender, 50 ether);

        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 50 ether, 100 ether)
        );
        token.transferFrom(owner, recipient, 100 ether);
    }

    function testTransferFromWithInfiniteAllowance() external {
        token.exposedMint(owner, 200 ether);

        vm.prank(owner);
        token.approve(spender, type(uint256).max);

        // First transfer
        vm.prank(spender);
        token.transferFrom(owner, recipient, 100 ether);
        assertEq(token.balanceOf(recipient), 100 ether);

        // Check allowance unchanged after first transfer (infinite allowance)
        assertEq(token.allowance(owner, spender), type(uint256).max);

        // Second transfer still succeeds without allowance change
        vm.prank(spender);
        token.transferFrom(owner, recipient, 100 ether);
        assertEq(token.balanceOf(recipient), 200 ether);

        // Allowance still unchanged
        assertEq(token.allowance(owner, spender), type(uint256).max);
    }

    // ============ _mint revert tests (via harness) ============

    function testMintRevertsOnZeroAddress() external {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.exposedMint(address(0), 100 ether);
    }

    // ============ _burn revert tests (via harness) ============

    function testBurnRevertsOnZeroAddress() external {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        token.exposedBurn(address(0), 100 ether);
    }

    // ============ additional coverage tests ============

    function testBurnRevertsOnInsufficientBalance() external {
        token.exposedMint(owner, 50 ether);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, 50 ether, 100 ether)
        );
        token.exposedBurn(owner, 100 ether);
    }

    function testApproveWithValueZero() external {
        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit IERC20.Approval(owner, spender, 0);
        token.approve(spender, 0);

        assertEq(token.allowance(owner, spender), 0);
    }

    function testApproveEmitsEvent() external {
        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        // IERC20 Approval event
        emit IERC20.Approval(owner, spender, 100 ether);
        token.approve(spender, 100 ether);
    }

    function testExposedApproveWithEmitEventFalse() external {
        // Test the internal _approve with emitEvent = false
        token.exposedApprove(owner, spender, 100 ether, false);
        assertEq(token.allowance(owner, spender), 100 ether);
    }

    function testExposedSpendAllowanceReducesAllowance() external {
        token.exposedMint(owner, 100 ether);
        token.exposedApprove(owner, spender, 100 ether, true);

        token.exposedSpendAllowance(owner, spender, 30 ether);
        assertEq(token.allowance(owner, spender), 70 ether);
    }

    function testExposedSpendAllowanceRevertsOnInsufficientAllowance() external {
        token.exposedMint(owner, 100 ether);
        token.exposedApprove(owner, spender, 50 ether, true);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 50 ether, 100 ether)
        );
        token.exposedSpendAllowance(owner, spender, 100 ether);
    }

    function testExposedSpendAllowanceWithMaxAllowanceDoesNotReduce() external {
        token.exposedMint(owner, 100 ether);
        token.exposedApprove(owner, spender, type(uint256).max, true);

        // Spending from max allowance should not reduce it
        token.exposedSpendAllowance(owner, spender, 100 ether);
        assertEq(token.allowance(owner, spender), type(uint256).max);
    }
}
