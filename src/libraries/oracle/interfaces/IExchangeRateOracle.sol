// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

interface IExchangeRateOracle {
    /// @notice Returns the current exchange rate scaled for SY accounting.
    /// @dev Oracle-backed SY adapters consume this as `asset per SY`. This interface does not add freshness,
    ///      bounds, fallback, or multi-source guarantees.
    /// @return The current exchange rate value.
    function getExchangeRate() external view returns (uint256);
}
