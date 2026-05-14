// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IWETH} from "./IWETH.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";

error NativeAmountMismatch();
error NativeTransferFailed();
error ArrayLengthMismatch();

abstract contract TokenHelper is ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @dev Sentinel used to route native token transfers instead of ERC20 calls.
    address internal constant NATIVE = address(0);
    /// @dev Approval refresh threshold; some tokens store allowances in 96 bits.
    uint256 internal constant LOWER_BOUND_APPROVAL = type(uint96).max / 2; // some tokens use 96 bits for approval

    /// @dev For native token inputs, `msg.value` must equal `amount`; for ERC20 inputs, it must be zero.
    function _transferIn(address token, address from, uint256 amount) internal {
        if (token == NATIVE) {
            if (msg.value != amount) revert NativeAmountMismatch();
        } else {
            if (msg.value != 0) revert NativeAmountMismatch();
            if (amount != 0) IERC20(token).safeTransferFrom(from, address(this), amount);
        }
    }

    /// @dev Skips the ERC20 call for zero amount transfers.
    function _transferFrom(IERC20 token, address from, address to, uint256 amount) internal {
        if (amount != 0) token.safeTransferFrom(from, to, amount);
    }

    /// @dev Skips zero amounts; native transfers revert with `NativeTransferFailed` when the call fails.
    function _transferOut(address token, address to, uint256 amount) internal {
        if (amount == 0) return;
        if (token == NATIVE) {
            (bool success,) = to.call{value: amount}("");
            if (!success) revert NativeTransferFailed();
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
    }

    /// @dev Transfers each token/amount pair and requires both arrays to have the same length.
    function _transferOut(address[] memory tokens, address to, uint256[] memory amounts) internal {
        uint256 numTokens = tokens.length;
        if (numTokens != amounts.length) revert ArrayLengthMismatch();
        for (uint256 i = 0; i < numTokens;) {
            _transferOut(tokens[i], to, amounts[i]);
            unchecked {
                ++i;
            }
        }
    }

    /// @dev Returns this contract's native balance for the sentinel, otherwise the ERC20 balance.
    function _selfBalance(address token) internal view returns (uint256) {
        return (token == NATIVE) ? address(this).balance : IERC20(token).balanceOf(address(this));
    }

    /// @dev Returns this contract's ERC20 balance.
    function _selfBalance(IERC20 token) internal view returns (uint256) {
        return token.balanceOf(address(this));
    }

    /// @notice Approves the stipulated contract to spend the given allowance in the given token
    /// @dev PLS PAY ATTENTION to tokens that requires the approval to be set to 0 before changing it
    function _safeApprove(address token, address to, uint256 value) internal {
        IERC20(token).forceApprove(to, value);
    }

    /// @dev Keeps ERC20 allowance at max once it falls below `LOWER_BOUND_APPROVAL`; native sentinel is ignored.
    function _safeApproveInf(address token, address to) internal {
        if (token == NATIVE) return;
        if (IERC20(token).allowance(address(this), to) < LOWER_BOUND_APPROVAL) {
            _safeApprove(token, to, 0);
            _safeApprove(token, to, type(uint256).max);
        }
    }

    /// @dev Wraps native token into WETH when `tokenIn` is sentinel; otherwise unwraps `tokenIn` WETH.
    // solhint-disable-next-line func-name-mixedcase
    function _wrap_unwrap_ETH(address tokenIn, address tokenOut, uint256 netTokenIn) internal {
        if (tokenIn == NATIVE) IWETH(tokenOut).deposit{value: netTokenIn}();
        else IWETH(tokenIn).withdraw(netTokenIn);
    }
}
