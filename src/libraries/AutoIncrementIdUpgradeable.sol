// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

abstract contract AutoIncrementIdUpgradeable is Initializable {
    /// @custom:storage-location erc7201:outrun.storage.AutoIncrementId
    struct AutoIncrementIdStorage {
        uint256 idCounter;
    }

    // keccak256(abi.encode(uint256(keccak256("outrun.storage.AutoIncrementId")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant AUTO_INCREMENT_ID_STORAGE_LOCATION =
        0xf89e69ccd0f0ce2bd1d8010b084ae175827f4bf65e4d8f8f0dcc892b62a15b00;

    function _getAutoIncrementIdStorage() private pure returns (AutoIncrementIdStorage storage $) {
        assembly {
            $.slot := AUTO_INCREMENT_ID_STORAGE_LOCATION
        }
    }

    function __AutoIncrementId_init() internal onlyInitializing {}

    function idCounter() public view returns (uint256) {
        return _getAutoIncrementIdStorage().idCounter;
    }

    function _nextId() internal returns (uint256) {
        AutoIncrementIdStorage storage $ = _getAutoIncrementIdStorage();
        unchecked {
            ++$.idCounter;
        }
        return $.idCounter;
    }
}
