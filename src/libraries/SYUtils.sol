// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

library SYUtils {
    uint256 internal constant ONE = 1e18;

    /// @notice Converts SY amount to asset amount, rounded down.
    /// @dev exchangeRate is asset per SY scaled by 1e18.
    function syToAsset(uint256 exchangeRate, uint256 syAmount) internal pure returns (uint256) {
        return (syAmount * exchangeRate) / ONE;
    }

    /// @notice Converts SY amount to asset amount, rounded up.
    /// @dev exchangeRate is asset per SY scaled by 1e18.
    function syToAssetUp(uint256 exchangeRate, uint256 syAmount) internal pure returns (uint256) {
        return (syAmount * exchangeRate + ONE - 1) / ONE;
    }

    /// @notice Converts asset amount to SY amount, rounded down.
    /// @dev exchangeRate is asset per SY scaled by 1e18.
    function assetToSy(uint256 exchangeRate, uint256 assetAmount) internal pure returns (uint256) {
        return (assetAmount * ONE) / exchangeRate;
    }

    /// @notice Converts asset amount to SY amount, rounded up.
    /// @dev exchangeRate is asset per SY scaled by 1e18.
    function assetToSyUp(uint256 exchangeRate, uint256 assetAmount) internal pure returns (uint256) {
        return (assetAmount * ONE + exchangeRate - 1) / exchangeRate;
    }
}
