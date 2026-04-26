// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {
    MessagingFee,
    MessagingParams
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {OutrunUniversalAssets} from "../../../src/assets/base/OutrunUniversalAssets.sol";

contract MockLzEndpoint {
    address internal delegate;
    uint256 internal quoteNativeFee;
    uint32 public eid;

    constructor() {
        eid = 1001;
    }

    function setEid(uint32 eid_) external {
        eid = eid_;
    }

    function setDelegate(address delegate_) external {
        delegate = delegate_;
    }

    function setQuoteNativeFee(uint256 nativeFee_) external {
        quoteNativeFee = nativeFee_;
    }

    function quote(MessagingParams calldata, address) external view returns (MessagingFee memory fee) {
        fee = MessagingFee({nativeFee: quoteNativeFee, lzTokenFee: 0});
    }

    function send(MessagingParams calldata, address) external payable returns (MessagingFee memory) {
        return MessagingFee({nativeFee: quoteNativeFee, lzTokenFee: 0});
    }
}

contract MockMsgInspector {
    function inspect(bytes calldata, bytes calldata) external pure returns (bool valid) {
        return true;
    }
}

contract OutrunOftHarness is OutrunUniversalAssets {
    constructor(string memory name_, string memory symbol_, uint8 decimals_, address _lzEndpoint, address _delegate)
        OutrunUniversalAssets(name_, symbol_, decimals_, _lzEndpoint, _delegate)
    {}

    function exposedCredit(address to, uint256 amountLD, uint32 srcEid) external returns (uint256) {
        return _credit(to, amountLD, srcEid);
    }

    function exposedDebit(address from, uint256 amountLD, uint256 minAmountLD, uint32 dstEid)
        external
        returns (uint256 amountSentLD, uint256 amountReceivedLD)
    {
        return _debit(from, amountLD, minAmountLD, dstEid);
    }

    function exposedToSD(uint256 amountLD) external view returns (uint64) {
        return _toSD(amountLD);
    }
}
