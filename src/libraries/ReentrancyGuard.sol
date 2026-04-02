// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

/**
 * @dev Outrun's ReentrancyGuard implementation, support transient variable.
 */
abstract contract ReentrancyGuard {
    bool private transient locked;
    error ReentrancyGuardReentrantCall();

    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() internal {
        require(!locked, ReentrancyGuardReentrantCall());
        locked = true;
    }

    function _nonReentrantAfter() internal {
        locked = false;
    }
}
