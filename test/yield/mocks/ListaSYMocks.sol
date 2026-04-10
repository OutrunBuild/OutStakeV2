// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {OutrunERC20} from "../../../src/assets/base/OutrunERC20.sol";

contract MockListaSlisBNB is OutrunERC20 {
    constructor() OutrunERC20("Lista slisBNB", "slisBNB", 18) {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external {
        _burn(account, amount);
    }
}

contract MockListaStakeManager {
    uint256 public exchangeRateQuote;
    MockListaSlisBNB public immutable slisBnb;

    constructor(MockListaSlisBNB slisBnb_) {
        slisBnb = slisBnb_;
    }

    function setExchangeRateQuote(uint256 newQuote) external {
        exchangeRateQuote = newQuote;
    }

    function deposit() external payable virtual {
        uint256 slisBnbOut = exchangeRateQuote == 0
            ? msg.value
            : msg.value * exchangeRateQuote / 1 ether;
        slisBnb.mint(msg.sender, slisBnbOut);
    }

    function convertBnbToSnBnb(uint256 amount) external view returns (uint256) {
        return exchangeRateQuote == 0 ? amount : amount * exchangeRateQuote / 1 ether;
    }

    function convertSnBnbToBnb(uint256 amount) external view returns (uint256) {
        return exchangeRateQuote == 0 ? amount : amount * 1 ether / exchangeRateQuote;
    }

    function getTotalPooledBnb() external pure returns (uint256) {
        return 1_000_000 ether;
    }
}

contract MockListaStakeManagerZeroDeposit is MockListaStakeManager {
    constructor(MockListaSlisBNB slisBnb_) MockListaStakeManager(slisBnb_) {}

    function deposit() external payable override {
        // intentionally do not mint any slisBNB
    }
}
