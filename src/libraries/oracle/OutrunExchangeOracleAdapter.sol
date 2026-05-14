// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {IExchangeRateOracle} from "./interfaces/IExchangeRateOracle.sol";
import {AggregatorInterface} from "./interfaces/AggregatorInterface.sol";

error InvalidOracleAnswer();

contract OutrunExchangeOracleAdapter is IExchangeRateOracle {
    /// @notice Underlying oracle that provides the raw exchange-rate answer.
    address public immutable oracle;
    /// @notice Target decimals configured at construction for normalized exchange rates.
    uint8 public immutable decimals;
    /// @notice Raw decimals reported by the underlying oracle at construction.
    uint8 public immutable rawDecimals;

    /// @dev Captures both target decimals and raw oracle decimals once; later oracle decimal changes are not tracked.
    constructor(address _oracle, uint8 _decimals) {
        oracle = _oracle;
        decimals = _decimals;
        rawDecimals = AggregatorInterface(_oracle).decimals();
    }

    /**
     * @notice Returns the latest oracle exchange rate scaled to the configured SY decimals.
     * @dev Reverts when the underlying oracle answer is non-positive. Does not apply freshness checks,
     * bounds checks, or fallback oracle logic.
     * @return The normalized exchange rate value.
     */
    function getExchangeRate() external view returns (uint256) {
        int256 answer = AggregatorInterface(oracle).latestAnswer();
        if (answer <= 0) revert InvalidOracleAnswer();
        // answer is checked to be strictly positive before converting to uint256.
        // forge-lint: disable-next-line(unsafe-typecast)
        return (uint256(answer) * 10 ** decimals) / 10 ** rawDecimals;
    }
}
