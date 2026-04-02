// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {OutrunERC20} from "../../src/assets/base/OutrunERC20.sol";
import {TokenHelper} from "../../src/libraries/TokenHelper.sol";
import {IMintable, OnlyFaucet} from "./MockUSDC.sol";

interface IMockSUSDS is IMintable {
    function wrap(uint256 amount) external returns (uint256);

    function unwrap(uint256 amount) external returns (uint256);
}

/**
 * @dev Just For Memeverse Genesis Test
 */
contract MockSUSDS is IMockSUSDS, OutrunERC20, TokenHelper {
    address public immutable MOCK_USDC;

    address public faucet;

    constructor(string memory _name, string memory _symbol, uint8 _decimals, address _mockUSDC, address _faucet)
        OutrunERC20(_name, _symbol, _decimals)
    {
        MOCK_USDC = _mockUSDC;
        faucet = _faucet;
    }

    function mint(address account, uint256 amount) external override {
        if (msg.sender != faucet) revert OnlyFaucet();
        _mint(account, amount);
    }

    function wrap(uint256 amount) external override returns (uint256) {
        _transferIn(MOCK_USDC, msg.sender, amount);
        _mint(msg.sender, amount);
        return amount;
    }

    function unwrap(uint256 amount) external override returns (uint256) {
        _burn(msg.sender, amount);
        _transferOut(MOCK_USDC, msg.sender, amount);
        return amount;
    }
}
