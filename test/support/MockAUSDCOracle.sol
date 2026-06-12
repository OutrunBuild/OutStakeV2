// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.35;

import {MockExchangeRateOracle} from "./MockExchangeRateOracle.sol";

/**
 * @dev Mock aUSDC Oracle
 */
contract MockAUSDCOracle is MockExchangeRateOracle {
    uint8 public constant DECIMALS = 18;
    uint8 public constant RAW_DECIMALS = 6;

    constructor(address _owner) MockExchangeRateOracle(_owner, 1000000) {}

    function _decimals() internal pure override returns (uint8) {
        return DECIMALS;
    }

    function _rawDecimals() internal pure override returns (uint8) {
        return RAW_DECIMALS;
    }
}
