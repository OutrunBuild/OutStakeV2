// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {TokenHelper} from "../../src/libraries/TokenHelper.sol";
import {NativeAmountMismatch, NativeTransferFailed} from "../../src/libraries/CommonErrors.sol";
import {IWETH} from "../../src/libraries/IWETH.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// Harness to expose internal functions
contract TokenHelperHarness is TokenHelper {
    constructor() {}

    function exposedTransferIn(address token, address from, uint256 amount) external payable {
        _transferIn(token, from, amount);
    }

    function exposedTransferOut(address token, address to, uint256 amount) external {
        _transferOut(token, to, amount);
    }

    function exposedSafeApprove(address token, address to, uint256 amount) external {
        _safeApprove(token, to, amount);
    }

    function exposedSafeApproveInf(address token, address to) external {
        _safeApproveInf(token, to);
    }

    function exposedSelfBalance(address token) external view returns (uint256) {
        return _selfBalance(token);
    }

    // Receive ETH for native transfers
    receive() external payable {}
}

// Mock ERC20 with mint capability
contract MockERC20 is ERC20 {
    constructor(string memory _name, string memory _symbol, uint8 _decimals) ERC20(_name, _symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// Mock WETH for testing wrap/unwrap
contract MockWETH is IWETH {
    string public name = "Wrapped Ether";
    string public symbol = "WETH";
    uint8 public decimals = 18;
    uint256 public override totalSupply;

    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;

    function deposit() external payable override {
        balanceOf[msg.sender] += msg.value;
        totalSupply += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    function withdraw(uint256 wad) external override {
        require(balanceOf[msg.sender] >= wad, "insufficient balance");
        balanceOf[msg.sender] -= wad;
        totalSupply -= wad;
        (bool success,) = msg.sender.call{value: wad}("");
        require(success, "withdraw failed");
        emit Withdrawal(msg.sender, wad);
    }

    function transfer(address to, uint256 value) external override returns (bool) {
        require(balanceOf[msg.sender] >= value, "insufficient balance");
        balanceOf[msg.sender] -= value;
        balanceOf[to] += value;
        emit Transfer(msg.sender, to, value);
        return true;
    }

    function approve(address spender, uint256 value) external override returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external override returns (bool) {
        require(balanceOf[from] >= value, "insufficient balance");
        require(allowance[from][msg.sender] >= value, "insufficient allowance");
        allowance[from][msg.sender] -= value;
        balanceOf[from] -= value;
        balanceOf[to] += value;
        emit Transfer(from, to, value);
        return true;
    }

    // solhint-disable-next-line no-complex-fallback
    receive() external payable {
        balanceOf[msg.sender] += msg.value;
        totalSupply += msg.value;
        emit Deposit(msg.sender, msg.value);
    }
}

    // Contract that always reverts in receive()
    contract RevertingReceiver {
        receive() external payable {
            revert("I don't accept ETH");
        }
    }

    // Pausable token for testing OutrunERC20Pausable
    contract PausableToken is ERC20, Pausable, Ownable {
        constructor() ERC20("Pausable Token", "PAUSE") Ownable(msg.sender) {}

        function _update(address from, address to, uint256 value) internal virtual override whenNotPaused {
            super._update(from, to, value);
        }

        function pause() external onlyOwner {
            _pause();
        }

        function unpause() external onlyOwner {
            _unpause();
        }

        function mint(address to, uint256 amount) external {
            _mint(to, amount);
        }
    }

    contract TokenHelperTest is Test {
        TokenHelperHarness internal harness;
        MockERC20 internal token;
        MockWETH internal weth;

        address internal owner = address(0xA11CE);
        address internal user = address(0xB0B);
        address internal recipient = address(0xCAFE);

        uint256 internal constant LOWER_BOUND_APPROVAL = type(uint96).max / 2;

        function setUp() external {
            harness = new TokenHelperHarness();
            token = new MockERC20("Test Token", "TST", 18);
            weth = new MockWETH();
        }

        // ============ _transferIn tests ============

        function testTransferInNativeChecksMsgValue() external {
            // ERC20 input with msg.value > 0 should revert
            vm.deal(address(harness), 0);

            vm.expectRevert(NativeAmountMismatch.selector);
            harness.exposedTransferIn{value: 1 ether}(address(token), user, 100 ether);
        }

        function testTransferInNativeWithValueMismatch() external {
            // Native input where msg.value != amount should revert
            vm.deal(address(harness), 2 ether);

            vm.expectRevert(NativeAmountMismatch.selector);
            harness.exposedTransferIn{value: 1 ether}(address(0), user, 2 ether);
        }

        function testTransferInNativeSucceeds() external {
            // Native input with correct msg.value should succeed
            vm.deal(user, 2 ether);

            vm.prank(user);
            (bool success,) = address(harness).call{value: 1 ether}("");
            assertTrue(success);
            assertEq(address(harness).balance, 1 ether);
        }

        function testTransferInERC20Succeeds() external {
            token.mint(user, 100 ether);

            vm.prank(user);
            token.approve(address(harness), 100 ether);

            harness.exposedTransferIn(address(token), user, 100 ether);

            assertEq(token.balanceOf(address(harness)), 100 ether);
            assertEq(token.balanceOf(user), 0);
        }

        function testTransferInERC20SkipsOnZeroAmount() external {
            // Zero amount should skip the transfer
            harness.exposedTransferIn(address(token), user, 0);
            assertEq(token.balanceOf(address(harness)), 0);
        }

        // ============ _transferOut tests ============

        function testTransferOutNativeSucceeds() external {
            vm.deal(address(harness), 1 ether);

            harness.exposedTransferOut(address(0), recipient, 0.5 ether);

            assertEq(recipient.balance, 0.5 ether);
            assertEq(address(harness).balance, 0.5 ether);
        }

        function testTransferOutNativeRevertsOnFailure() external {
            RevertingReceiver receiver = new RevertingReceiver();
            vm.deal(address(harness), 1 ether);

            vm.expectRevert(NativeTransferFailed.selector);
            harness.exposedTransferOut(address(0), address(receiver), 0.5 ether);
        }

        function testTransferOutSkipsOnZeroAmount() external {
            vm.deal(address(harness), 1 ether);

            // Should not transfer anything
            harness.exposedTransferOut(address(token), recipient, 0);

            assertEq(token.balanceOf(recipient), 0);
            assertEq(address(harness).balance, 1 ether); // unchanged
        }

        function testTransferOutERC20Succeeds() external {
            token.mint(address(harness), 100 ether);

            harness.exposedTransferOut(address(token), recipient, 50 ether);

            assertEq(token.balanceOf(recipient), 50 ether);
            assertEq(token.balanceOf(address(harness)), 50 ether);
        }

        // ============ _safeApprove tests ============

        function testSafeApproveSetsAllowance() external {
            token.mint(address(harness), 100 ether);

            harness.exposedSafeApprove(address(token), recipient, 50 ether);

            assertEq(token.allowance(address(harness), recipient), 50 ether);
        }

        function testSafeApproveSetsToZero() external {
            token.mint(address(harness), 100 ether);

            harness.exposedSafeApprove(address(token), recipient, 50 ether);
            assertEq(token.allowance(address(harness), recipient), 50 ether);

            harness.exposedSafeApprove(address(token), recipient, 0);
            assertEq(token.allowance(address(harness), recipient), 0);
        }

        // ============ _safeApproveInf tests ============

        function testSafeApproveInfSetsToMax() external {
            token.mint(address(harness), 100 ether);

            // Current allowance is 0, which is < LOWER_BOUND_APPROVAL
            harness.exposedSafeApproveInf(address(token), recipient);

            assertEq(token.allowance(address(harness), recipient), type(uint256).max);
        }

        function testSafeApproveInfSkipsWhenSufficient() external {
            token.mint(address(harness), 100 ether);

            // Set allowance to a value >= LOWER_BOUND_APPROVAL
            harness.exposedSafeApprove(address(token), recipient, LOWER_BOUND_APPROVAL);

            uint256 allowanceBefore = token.allowance(address(harness), recipient);
            assertEq(allowanceBefore, LOWER_BOUND_APPROVAL);

            // Should skip since allowance is already >= LOWER_BOUND_APPROVAL
            harness.exposedSafeApproveInf(address(token), recipient);

            // Allowance should remain unchanged
            assertEq(token.allowance(address(harness), recipient), allowanceBefore);
        }

        function testSafeApproveInfSetsToMaxWhenBelowLowerBound() external {
            token.mint(address(harness), 100 ether);

            // Set allowance to a value < LOWER_BOUND_APPROVAL
            harness.exposedSafeApprove(address(token), recipient, 100 ether);
            assertEq(token.allowance(address(harness), recipient), 100 ether);

            // Should set to max since current < LOWER_BOUND_APPROVAL
            harness.exposedSafeApproveInf(address(token), recipient);

            assertEq(token.allowance(address(harness), recipient), type(uint256).max);
        }

        function testSafeApproveInfSkipsForNative() external {
            // Should return immediately for native token without any approval
            harness.exposedSafeApproveInf(address(0), recipient);
            // No assertion needed, just ensure no revert
        }

        // ============ _selfBalance tests ============

        function testSelfBalanceNative() external {
            vm.deal(address(harness), 5 ether);

            uint256 balance = harness.exposedSelfBalance(address(0));
            assertEq(balance, 5 ether);
        }

        function testSelfBalanceERC20() external {
            token.mint(address(harness), 100 ether);

            uint256 balance = harness.exposedSelfBalance(address(token));
            assertEq(balance, 100 ether);
        }

        function testSelfBalanceZeroNative() external {
            uint256 balance = harness.exposedSelfBalance(address(0));
            assertEq(balance, 0);
        }

        function testSelfBalanceZeroERC20() external {
            uint256 balance = harness.exposedSelfBalance(address(token));
            assertEq(balance, 0);
        }

        // ============ LOWER_BOUND_APPROVAL constant test ============

        function testLowerBoundApprovalValue() external {
            assertEq(LOWER_BOUND_APPROVAL, type(uint96).max / 2);
        }
    }

    contract OutrunERC20PausableTest is Test {
        PausableToken internal token;

        address internal owner = address(0xA11CE);
        address internal user = address(0xB0B);
        address internal recipient = address(0xCAFE);

        function setUp() external {
            vm.prank(owner);
            token = new PausableToken();
        }

        function testTransferRevertsWhenPaused() external {
            token.mint(user, 100 ether);

            vm.prank(owner);
            token.pause();

            vm.prank(user);
            vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
            token.transfer(recipient, 50 ether);
        }

        function testTransferSucceedsAfterUnpause() external {
            token.mint(user, 100 ether);

            vm.prank(owner);
            token.pause();

            vm.prank(user);
            vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
            token.transfer(recipient, 50 ether);

            vm.prank(owner);
            token.unpause();

            vm.prank(user);
            assertTrue(token.transfer(recipient, 50 ether));
            assertEq(token.balanceOf(recipient), 50 ether);
            assertEq(token.balanceOf(user), 50 ether);
        }

        function testMintRevertsWhenPaused() external {
            vm.prank(owner);
            token.pause();

            vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
            token.mint(user, 100 ether);
        }

        function testPauseOnlyOwner() external {
            vm.prank(user);
            vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
            token.pause();
        }

        function testUnpauseOnlyOwner() external {
            vm.prank(owner);
            token.pause();

            vm.prank(user);
            vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
            token.unpause();
        }
    }
