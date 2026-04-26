// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {OFTCore} from "@layerzerolabs/oft-evm/contracts/OFTCore.sol";
import {OFTFeeDetail, OFTLimit, OFTReceipt, SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {RateLimiter} from "@layerzerolabs/oapp-evm/contracts/oapp/utils/RateLimiter.sol";

import {OutrunERC20} from "../base/OutrunERC20.sol";
import {OutrunERC20Pausable} from "../base/OutrunERC20Pausable.sol";

/**
 * @title Outrun OFT Contract
 * @dev OFT is an ERC-20 token that extends the functionality of the OFTCore contract.
 *      Inherits LayerZero's RateLimiter for outbound rate limiting using the official
 *      _outflow / _setRateLimits / _amountCanBeSent interface.
 */
abstract contract OutrunOFT is OutrunERC20Pausable, OFTCore, RateLimiter {
    error InvalidWindowSeconds();

    // ── Events ──────────────────────────────────────────────────────────────

    event OutboundRateLimitSet(uint32 indexed eid, uint192 limit, uint64 window);
    event OutboundRateLimitRemoved(uint32 indexed eid);

    constructor(string memory name_, string memory symbol_, uint8 decimals_, address _lzEndpoint, address _delegate)
        OutrunERC20(name_, symbol_, decimals_)
        OFTCore(decimals_, _lzEndpoint, _delegate)
    {}

    function token() public view returns (address) {
        return address(this);
    }

    function approvalRequired() external pure virtual returns (bool) {
        return false;
    }

    /**
     * @dev Override to align view with execution semantics for unconfigured peers.
     *      LayerZero's default returns amountCanBeSent == 0 for unconfigured peers (window == 0).
     *      Returns _maxOFTAmountLD() instead to avoid accidentally blocking channels.
     */
    function getAmountCanBeSent(uint32 _dstEid)
        public
        view
        virtual
        override
        returns (uint256 currentAmountInFlight, uint256 amountCanBeSent)
    {
        RateLimit storage rl = rateLimits[_dstEid];
        if (rl.window == 0) return (0, _maxOFTAmountLD());
        return _amountCanBeSent(rl.amountInFlight, rl.lastUpdated, rl.limit, rl.window);
    }

    // ── Rate-limit admin setters ───────────────────────────────────────────

    function setOutboundRateLimit(uint32 dstEid, uint192 limit, uint64 window) external onlyOwner {
        if (window == 0) revert InvalidWindowSeconds();
        RateLimitConfig[] memory configs = new RateLimitConfig[](1);
        configs[0] = RateLimitConfig({dstEid: dstEid, limit: limit, window: window});
        _setRateLimits(configs);
        emit OutboundRateLimitSet(dstEid, limit, window);
    }

    function removeOutboundRateLimit(uint32 dstEid) external onlyOwner {
        delete rateLimits[dstEid];
        emit OutboundRateLimitRemoved(dstEid);
    }

    // ── Overrides ──────────────────────────────────────────────────────────

    /**
     * @dev Override quoteOFT to report real rate-limited capacity in oftLimit.maxAmountLD.
     *      LayerZero default uses totalSupply() as a placeholder.
     */
    function quoteOFT(SendParam calldata _sendParam)
        external
        view
        virtual
        override
        returns (OFTLimit memory oftLimit, OFTFeeDetail[] memory oftFeeDetails, OFTReceipt memory oftReceipt)
    {
        uint256 maxAmountLD = _removeDust(_maxQuoteAmountLD(_sendParam.dstEid));
        oftLimit = OFTLimit({minAmountLD: 0, maxAmountLD: maxAmountLD});

        oftFeeDetails = new OFTFeeDetail[](0);

        (uint256 amountSentLD, uint256 amountReceivedLD) =
            _debitView(_sendParam.amountLD, _sendParam.minAmountLD, _sendParam.dstEid);
        oftReceipt = OFTReceipt({amountSentLD: amountSentLD, amountReceivedLD: amountReceivedLD});
    }

    // slither-disable-next-line timestamp
    function _debit(address _from, uint256 _amountLD, uint256 _minAmountLD, uint32 _dstEid)
        internal
        virtual
        override
        returns (uint256 amountSentLD, uint256 amountReceivedLD)
    {
        (amountSentLD, amountReceivedLD) = _debitView(_amountLD, _minAmountLD, _dstEid);
        if (rateLimits[_dstEid].window != 0) _outflow(_dstEid, amountSentLD);
        _burn(_from, amountSentLD);
    }

    function _credit(address _to, uint256 _amountLD, uint32)
        internal
        virtual
        override
        returns (uint256 amountReceivedLD)
    {
        if (_to == address(0x0)) _to = address(0xdead);
        _mint(_to, _amountLD);
        return _amountLD;
    }

    function _maxQuoteAmountLD(uint32 dstEid) internal view returns (uint256) {
        uint256 maxAmountLD = _maxOFTAmountLD();
        RateLimit storage rl = rateLimits[dstEid];
        if (rl.window == 0) return maxAmountLD;

        (, uint256 amountCanBeSent) = _amountCanBeSent(rl.amountInFlight, rl.lastUpdated, rl.limit, rl.window);
        return amountCanBeSent < maxAmountLD ? amountCanBeSent : maxAmountLD;
    }

    function _maxOFTAmountLD() internal view returns (uint256) {
        return uint256(type(uint64).max) * decimalConversionRate;
    }
}
