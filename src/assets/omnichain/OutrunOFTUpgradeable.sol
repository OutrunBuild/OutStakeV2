// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// solhint-disable-next-line import-path-check
import {OFTCoreUpgradeable} from "@layerzerolabs/oft-evm-upgradeable/contracts/oft/OFTCoreUpgradeable.sol";
import {OFTFeeDetail, OFTLimit, OFTReceipt, SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";

import {OutrunERC20PausableUpgradeable} from "../base/OutrunERC20PausableUpgradeable.sol";
import {OutrunERC20Upgradeable} from "../base/OutrunERC20Upgradeable.sol";
import {OutrunRateLimiterUpgradeable} from "./OutrunRateLimiterUpgradeable.sol";

abstract contract OutrunOFTUpgradeable is
    OutrunERC20PausableUpgradeable,
    OFTCoreUpgradeable,
    OutrunRateLimiterUpgradeable
{
    uint8 private immutable _localDecimals;

    error InvalidLayerZeroEndpoint();
    error InvalidWindowSeconds();

    event OutboundRateLimitSet(uint32 indexed eid, uint192 limit, uint64 window);
    event OutboundRateLimitRemoved(uint32 indexed eid);

    constructor(uint8 localDecimals_, address lzEndpoint) OFTCoreUpgradeable(localDecimals_, lzEndpoint) {
        if (lzEndpoint == address(0)) revert InvalidLayerZeroEndpoint();
        _localDecimals = localDecimals_;
        _disableInitializers();
    }

    // solhint-disable-next-line func-name-mixedcase
    function __OutrunOFT_init(string memory name_, string memory symbol_, uint8 decimals_, address owner_)
        internal
        onlyInitializing
    {
        __OutrunERC20Pausable_init(name_, symbol_, decimals_, owner_);
        __OutrunRateLimiter_init();
        __OFTCore_init(owner_);
    }

    function token() public view returns (address) {
        return address(this);
    }

    function approvalRequired() external pure virtual returns (bool) {
        return false;
    }

    function localDecimals() public view returns (uint8) {
        return _localDecimals;
    }

    function getAmountCanBeSent(uint32 dstEid)
        public
        view
        virtual
        override
        returns (uint256 currentAmountInFlight, uint256 amountCanBeSent)
    {
        RateLimit memory rl = rateLimits(dstEid);
        if (rl.window == 0) return (0, _maxOFTAmountLD());
        return _amountCanBeSent(rl.amountInFlight, rl.lastUpdated, rl.limit, rl.window);
    }

    function setOutboundRateLimit(uint32 dstEid, uint192 limit, uint64 window) external onlyOwner {
        if (window == 0) revert InvalidWindowSeconds();
        RateLimitConfig[] memory configs = new RateLimitConfig[](1);
        configs[0] = RateLimitConfig({dstEid: dstEid, limit: limit, window: window});
        _setRateLimits(configs);
        emit OutboundRateLimitSet(dstEid, limit, window);
    }

    function removeOutboundRateLimit(uint32 dstEid) external onlyOwner {
        _deleteRateLimit(dstEid);
        emit OutboundRateLimitRemoved(dstEid);
    }

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

    function _debit(address _from, uint256 _amountLD, uint256 _minAmountLD, uint32 _dstEid)
        internal
        virtual
        override
        returns (uint256 amountSentLD, uint256 amountReceivedLD)
    {
        (amountSentLD, amountReceivedLD) = _debitView(_amountLD, _minAmountLD, _dstEid);
        if (rateLimits(_dstEid).window != 0) _outflow(_dstEid, amountSentLD);
        // Outbound debit must respect pause.
        _update(_from, address(0), amountSentLD);
    }

    function _credit(address _to, uint256 _amountLD, uint32)
        internal
        virtual
        override
        returns (uint256 amountReceivedLD)
    {
        if (_to == address(0)) _to = address(0xdead);
        // Cross-chain delivery must not revert during pause.
        OutrunERC20Upgradeable._update(address(0), _to, _amountLD);
        return _amountLD;
    }

    // slither-disable-next-line timestamp
    function _maxQuoteAmountLD(uint32 dstEid) internal view returns (uint256) {
        uint256 maxAmountLD = _maxOFTAmountLD();
        RateLimit memory rl = rateLimits(dstEid);
        if (rl.window == 0) return maxAmountLD;
        (, uint256 amountCanBeSent) = _amountCanBeSent(rl.amountInFlight, rl.lastUpdated, rl.limit, rl.window);
        return amountCanBeSent < maxAmountLD ? amountCanBeSent : maxAmountLD;
    }

    function _maxOFTAmountLD() internal view returns (uint256) {
        return uint256(type(uint64).max) * decimalConversionRate;
    }

    function _localDecimalsForValidation() internal view returns (uint8) {
        return _localDecimals;
    }
}
