// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

abstract contract OutrunRateLimiterUpgradeable is Initializable {
    struct RateLimit {
        // Packed layout follows current LayerZero OApp RateLimiter.
        uint192 amountInFlight;
        uint64 lastUpdated;
        uint192 limit;
        uint64 window;
    }

    struct RateLimitConfig {
        // Packed layout follows current LayerZero OApp RateLimiter.
        uint32 dstEid;
        uint192 limit;
        uint64 window;
    }

    /// @custom:storage-location erc7201:outrun.storage.OutrunRateLimiter
    struct OutrunRateLimiterStorage {
        mapping(uint32 dstEid => RateLimit limit) rateLimits;
    }

    // keccak256(abi.encode(uint256(keccak256("outrun.storage.OutrunRateLimiter")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant OUTRUN_RATE_LIMITER_STORAGE_LOCATION =
        0xd48bb12cf4270f606da51b56ba6371646e75d13e96dee8184b97a52adeda4000;

    event RateLimitsChanged(RateLimitConfig[] rateLimitConfigs);

    error RateLimitExceeded();

    function _getOutrunRateLimiterStorage() private pure returns (OutrunRateLimiterStorage storage $) {
        // slither-disable-next-line assembly
        assembly {
            $.slot := OUTRUN_RATE_LIMITER_STORAGE_LOCATION
        }
    }

    function __OutrunRateLimiter_init() internal onlyInitializing {}

    function rateLimits(uint32 dstEid) public view returns (RateLimit memory) {
        return _getOutrunRateLimiterStorage().rateLimits[dstEid];
    }

    function getAmountCanBeSent(uint32 dstEid)
        public
        view
        virtual
        returns (uint256 currentAmountInFlight, uint256 amountCanBeSent)
    {
        RateLimit memory rl = rateLimits(dstEid);
        return _amountCanBeSent(rl.amountInFlight, rl.lastUpdated, rl.limit, rl.window);
    }

    function _setRateLimits(RateLimitConfig[] memory rateLimitConfigs) internal virtual {
        OutrunRateLimiterStorage storage $ = _getOutrunRateLimiterStorage();
        uint256 numConfigs = rateLimitConfigs.length;
        unchecked {
            for (uint256 i; i < numConfigs; ++i) {
                RateLimit storage rl = $.rateLimits[rateLimitConfigs[i].dstEid];
                _checkpointRateLimit(rateLimitConfigs[i].dstEid);
                rl.limit = rateLimitConfigs[i].limit;
                rl.window = rateLimitConfigs[i].window;
            }
        }
        emit RateLimitsChanged(rateLimitConfigs);
    }

    // slither-disable-next-line timestamp
    function _amountCanBeSent(uint192 amountInFlight, uint64 lastUpdated, uint192 limit, uint64 window)
        internal
        view
        virtual
        returns (uint256 currentAmountInFlight, uint256 amountCanBeSent)
    {
        // slither-disable-next-line timestamp
        uint256 timeSinceLastDeposit = block.timestamp - lastUpdated;
        if (timeSinceLastDeposit >= window) return (0, limit);
        uint256 decay = (uint256(limit) * timeSinceLastDeposit) / window;
        currentAmountInFlight = amountInFlight <= decay ? 0 : amountInFlight - decay;
        amountCanBeSent = limit <= currentAmountInFlight ? 0 : limit - currentAmountInFlight;
    }

    // slither-disable-next-line timestamp
    function _outflow(uint32 dstEid, uint256 amount) internal virtual {
        _checkAndUpdateRateLimit(dstEid, amount);
    }

    function _checkpointRateLimit(uint32 dstEid) internal {
        _checkAndUpdateRateLimit(dstEid, 0);
    }

    // slither-disable-next-line timestamp
    function _checkAndUpdateRateLimit(uint32 dstEid, uint256 amount) internal {
        OutrunRateLimiterStorage storage $ = _getOutrunRateLimiterStorage();
        RateLimit storage rl = $.rateLimits[dstEid];
        (uint256 currentAmountInFlight, uint256 amountCanBeSent) =
            _amountCanBeSent(rl.amountInFlight, rl.lastUpdated, rl.limit, rl.window);
        if (amount > amountCanBeSent) revert RateLimitExceeded();
        // casting to uint192 is safe because currentAmountInFlight + amount is bounded by rl.limit.
        // forge-lint: disable-next-line(unsafe-typecast)
        rl.amountInFlight = uint192(currentAmountInFlight + amount);
        // slither-disable-next-line timestamp
        rl.lastUpdated = uint64(block.timestamp);
    }

    function _deleteRateLimit(uint32 dstEid) internal {
        delete _getOutrunRateLimiterStorage().rateLimits[dstEid];
    }
}
