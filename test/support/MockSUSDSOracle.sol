// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.35;

import {MockExchangeRateOracle} from "./MockExchangeRateOracle.sol";

/**
 * @dev Mock sUSDS Oracle
 */
contract MockSUSDSOracle is MockExchangeRateOracle {
    uint8 public constant DECIMALS = 18;
    uint8 public constant RAW_DECIMALS = 18;

    constructor(address _owner) MockExchangeRateOracle(_owner, 1e18) {}

    function _decimals() internal pure override returns (uint8) {
        return DECIMALS;
    }

    function _rawDecimals() internal pure override returns (uint8) {
        return RAW_DECIMALS;
    }
}
