// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

interface IExchangeRateOracle {
    /// @notice Returns the current exchange rate scaled for SY accounting.
    /// @dev Implementations are expected to expose the latest conversion rate.
    /// @return The current exchange rate value.
    function getExchangeRate() external view returns (uint256);
}
