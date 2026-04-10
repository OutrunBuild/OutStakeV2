// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {OutrunERC20} from "../../../src/assets/base/OutrunERC20.sol";

// Task 1 只需要最小 mock，先把 Aster 相关外部行为钉死。
contract MockAsBNB is OutrunERC20 {
    constructor() OutrunERC20("Aster asBNB", "asBNB", 18) {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }
}

contract MockSlisBNB is OutrunERC20 {
    mapping(address owner => mapping(address spender => uint256 count)) public approveCallCount;

    constructor() OutrunERC20("Lista slisBNB", "slisBNB", 18) {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external {
        _burn(account, amount);
    }

    function approve(address spender, uint256 value) external override returns (bool) {
        approveCallCount[msg.sender][spender]++;
        _approve(msg.sender, spender, value);
        return true;
    }
}

contract MockListaBNBStakeManager {
    uint256 public quote;

    function setQuote(uint256 newQuote) external {
        quote = newQuote;
    }

    function convertBnbToSnBnb(uint256 amount) external view returns (uint256) {
        return quote == 0 ? amount : amount * quote / 1 ether;
    }
}

contract MockYieldProxy {
    address public stakeManager;

    constructor(address stakeManager_) {
        stakeManager = stakeManager_;
    }

    function setStakeManager(address newStakeManager) external {
        stakeManager = newStakeManager;
    }
}

contract MockAsBnbMinter {
    address public asBnb;
    address public token;
    address public yieldProxy;

    uint256 public exchangeRateQuote;
    uint256 public convertToAsBnbQuote;

    uint256 public lastMintAmount;
    uint256 public lastNativeMintValue;

    bool public queueMode;

    constructor(address asBnb_, address token_, address yieldProxy_) {
        asBnb = asBnb_;
        token = token_;
        yieldProxy = yieldProxy_;
    }

    function setAsBnb(address newAsBnb) external {
        asBnb = newAsBnb;
    }

    function setToken(address newToken) external {
        token = newToken;
    }

    function setYieldProxy(address newYieldProxy) external {
        yieldProxy = newYieldProxy;
    }

    function setExchangeRateQuote(uint256 newQuote) external {
        exchangeRateQuote = newQuote;
    }

    function setConvertToAsBnbQuote(uint256 newQuote) external {
        convertToAsBnbQuote = newQuote;
    }

    function setQueueMode(bool newMode) external {
        queueMode = newMode;
    }

    function mintAsBnb(uint256 amount) external returns (uint256 amountOut) {
        lastMintAmount = amount;
        if (queueMode) return 0;

        MockSlisBNB(token).transferFrom(msg.sender, address(this), amount);
        MockSlisBNB(token).burn(address(this), amount);

        amountOut = convertToAsBnbQuote == 0 ? amount : amount * convertToAsBnbQuote / 1 ether;
        MockAsBNB(asBnb).mint(msg.sender, amountOut);
    }

    function mintAsBnb() external payable returns (uint256 amountOut) {
        lastNativeMintValue = msg.value;
        if (queueMode) return 0;

        uint256 slisBnbAmount =
            MockListaBNBStakeManager(MockYieldProxy(yieldProxy).stakeManager()).convertBnbToSnBnb(msg.value);
        amountOut = convertToAsBnbQuote == 0 ? slisBnbAmount : slisBnbAmount * convertToAsBnbQuote / 1 ether;
        MockAsBNB(asBnb).mint(msg.sender, amountOut);
    }

    function convertToTokens(uint256 amount) external view returns (uint256) {
        return exchangeRateQuote == 0 ? amount : amount * exchangeRateQuote / 1 ether;
    }

    function convertToAsBnb(uint256 amount) external view returns (uint256) {
        return convertToAsBnbQuote == 0 ? amount : amount * convertToAsBnbQuote / 1 ether;
    }
}
