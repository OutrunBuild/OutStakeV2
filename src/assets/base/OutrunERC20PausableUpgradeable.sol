// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {OutrunERC20Upgradeable} from "./OutrunERC20Upgradeable.sol";

abstract contract OutrunERC20PausableUpgradeable is OutrunERC20Upgradeable, PausableUpgradeable, OwnableUpgradeable {
    function __OutrunERC20Pausable_init(string memory name_, string memory symbol_, uint8 decimals_, address owner_)
        internal
        onlyInitializing
    {
        __OutrunERC20_init(name_, symbol_, decimals_);
        __Pausable_init();
        __Ownable_init(owner_);
    }

    function _update(address from, address to, uint256 value) internal virtual override whenNotPaused {
        super._update(from, to, value);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
