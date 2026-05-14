// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {WadRayMath} from "./WadRayMath.sol";

library AaveAdapterLib {
    /// @notice Converts Aave shares to assets using a ray-scaled liquidity index, rounded down.
    function calcSharesToAssetDown(uint256 amountShares, uint256 index) internal pure returns (uint256) {
        return (amountShares * index) / WadRayMath.RAY;
    }

    /// @notice Converts assets to Aave shares using a ray-scaled liquidity index, rounded down.
    function calcSharesFromAssetDown(uint256 amountAssets, uint256 index) internal pure returns (uint256) {
        return (amountAssets * WadRayMath.RAY) / index;
    }

    /// @notice Converts assets to Aave shares using a ray-scaled liquidity index, rounded half up.
    function calcSharesFromAssetUp(uint256 amountAssets, uint256 index) internal pure returns (uint256) {
        return WadRayMath.rayDiv(amountAssets, index);
    }
}
