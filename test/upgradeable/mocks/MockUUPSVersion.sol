// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {OutrunUniversalAssetsUpgradeable} from "../../../src/assets/base/OutrunUniversalAssetsUpgradeable.sol";
import {OutrunStakingPositionUpgradeable} from "../../../src/position/OutrunStakingPositionUpgradeable.sol";

contract MockUAssetUUPSV2 is OutrunUniversalAssetsUpgradeable {
    constructor(uint8 localDecimals, address lzEndpoint) OutrunUniversalAssetsUpgradeable(localDecimals, lzEndpoint) {}

    function version() external pure returns (uint256) {
        return 2;
    }
}

contract MockUAssetUUPSV2DifferentSharedDecimals is MockUAssetUUPSV2 {
    constructor(uint8 localDecimals, address lzEndpoint) MockUAssetUUPSV2(localDecimals, lzEndpoint) {}

    function sharedDecimals() public pure override returns (uint8) {
        return 8;
    }
}

contract MockPositionUUPSV2 is OutrunStakingPositionUpgradeable {
    function version() external pure returns (uint256) {
        return 2;
    }
}
