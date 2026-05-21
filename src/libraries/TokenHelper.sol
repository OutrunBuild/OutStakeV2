// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IWETH} from "./IWETH.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";

error NativeAmountMismatch();
error NativeTransferFailed();
error ArrayLengthMismatch();

/// @title TokenHelper
/// @notice Shared helper for native-token and ERC20 transfers.
/// @dev NATIVE (address(0)) is a sentinel that routes to ETH/BNB handling instead of ERC20 calls.
abstract contract TokenHelper is ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @dev Sentinel used to route native token transfers instead of ERC20 calls.
    /// When token == NATIVE (address(0)), the helper treats the operation as a native token
    /// transfer (ETH on Ethereum, BNB on BSC) instead of calling ERC20 methods. This lets a
    /// single code path handle both native and ERC20 tokens.
    address internal constant NATIVE = address(0);
    /// @dev Approval refresh threshold.
    /// Some ERC20 tokens (like USDT) store allowances in 96 bits. When the remaining allowance
    /// drops below half of uint96 max, we reset to max to avoid approval race conditions.
    uint256 internal constant LOWER_BOUND_APPROVAL = type(uint96).max / 2; // some tokens use 96 bits for approval

    /// @notice Transfers token from user; native via msg.value or ERC20 via transferFrom.
    /// @param token Address of the token to transfer (NATIVE sentinel for ETH/BNB).
    /// @param from Address to pull the token from.
    /// @param amount Amount of token to transfer.
    /// @dev For native token inputs, `msg.value` must equal `amount`; for ERC20 inputs, it must be zero.
    function _transferIn(address token, address from, uint256 amount) internal {
        if (token == NATIVE) {
            // For native token: msg.value must match the amount exactly — the caller sends ETH/BNB with the transaction.
            if (msg.value != amount) revert NativeAmountMismatch();
        } else {
            // For ERC20: msg.value must be 0 — funds are pulled via safeTransferFrom.
            if (msg.value != 0) revert NativeAmountMismatch();
            if (amount != 0) IERC20(token).safeTransferFrom(from, address(this), amount);
        }
    }

    /// @notice ERC20 transferFrom, skips zero amounts.
    /// @param token The ERC20 token to transfer.
    /// @param from Address to pull tokens from.
    /// @param to Address to transfer tokens to.
    /// @param amount Amount of tokens to transfer.
    /// @dev Skips the ERC20 call for zero amount transfers.
    function _transferFrom(IERC20 token, address from, address to, uint256 amount) internal {
        if (amount != 0) token.safeTransferFrom(from, to, amount);
    }

    /// @notice Transfers token out; native via low-level call or ERC20 transfer.
    /// @param token Address of the token to transfer (NATIVE sentinel for ETH/BNB).
    /// @param to Address to receive the tokens.
    /// @param amount Amount of token to transfer.
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

    /// @notice Batch transfer out of multiple tokens to a single receiver.
    /// @param tokens Array of token addresses to transfer.
    /// @param to Address to receive all tokens.
    /// @param amounts Array of amounts corresponding to each token.
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

    /// @notice Returns this contract's native balance for NATIVE, ERC20 balance otherwise.
    /// @param token Address of the token to query (NATIVE sentinel for ETH/BNB).
    /// @return The token balance held by this contract.
    /// @dev Returns this contract's native balance for the sentinel, otherwise the ERC20 balance.
    function _selfBalance(address token) internal view returns (uint256) {
        return (token == NATIVE) ? address(this).balance : IERC20(token).balanceOf(address(this));
    }

    /// @notice Returns this contract's ERC20 balance for the given token.
    /// @param token The ERC20 token to query.
    /// @return The ERC20 balance held by this contract.
    /// @dev Returns this contract's ERC20 balance.
    function _selfBalance(IERC20 token) internal view returns (uint256) {
        return token.balanceOf(address(this));
    }

    /// @notice forceApprove to the given spender
    /// @param token Address of the ERC20 token.
    /// @param to Address to approve as spender.
    /// @param value Amount to approve.
    /// @dev PLS PAY ATTENTION to tokens that requires the approval to be set to 0 before changing it
    function _safeApprove(address token, address to, uint256 value) internal {
        IERC20(token).forceApprove(to, value);
    }

    /// @notice Keeps allowance at max; resets to 0 first because some tokens reject non-zero-to-non-zero.
    /// @param token Address of the ERC20 token.
    /// @param to Address to approve as spender.
    /// @dev Keeps ERC20 allowance at max once it falls below `LOWER_BOUND_APPROVAL`; native sentinel is ignored.
    function _safeApproveInf(address token, address to) internal {
        if (token == NATIVE) return;
        if (IERC20(token).allowance(address(this), to) < LOWER_BOUND_APPROVAL) {
            // First reset to 0 (required by tokens that reject non-zero-to-non-zero approval changes), then set to max.
            _safeApprove(token, to, 0);
            _safeApprove(token, to, type(uint256).max);
        }
    }

    /// @notice Wraps native to WETH or unwraps WETH to native.
    /// @param tokenIn Input token (NATIVE to wrap, WETH address to unwrap).
    /// @param tokenOut Output token (WETH address when wrapping, ignored when unwrapping).
    /// @param netTokenIn Amount of input token.
    /// @dev Wraps native token into WETH when `tokenIn` is sentinel; otherwise unwraps `tokenIn` WETH.
    /// Handles WETH wrap/unwrap. When tokenIn is NATIVE: wraps native ETH into the WETH-like
    /// tokenOut. Otherwise: unwraps tokenIn (WETH) back to native ETH.
    // solhint-disable-next-line func-name-mixedcase
    function _wrap_unwrap_ETH(address tokenIn, address tokenOut, uint256 netTokenIn) internal {
        if (tokenIn == NATIVE) IWETH(tokenOut).deposit{value: netTokenIn}();
        else IWETH(tokenIn).withdraw(netTokenIn);
    }
}
