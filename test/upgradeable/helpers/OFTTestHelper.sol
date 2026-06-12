// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.35;

import {
    MessagingFee,
    MessagingParams
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

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
