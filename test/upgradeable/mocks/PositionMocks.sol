// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.35;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockSY} from "./PositionTestMocks.sol";

/// @title PositionMockToken
/// @notice Simple ERC20 with a public mint, used as the underlying yield token in position tests.
contract PositionMockToken is ERC20 {
    constructor() ERC20("Yield Token", "YBT") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @title PositionMockOracle
/// @notice Fixed 1:1 exchange rate oracle for position tests.
contract PositionMockOracle {
    function getExchangeRate() external pure returns (uint256) {
        return 1e18;
    }
}

/// @title RejectZeroTransferMockSY
/// @notice Mock SY that reverts on zero-amount transfers, used to verify keepRedeem
///         skips the owner transfer when the excess is zero.
contract RejectZeroTransferMockSY is MockSY {
    constructor(address underlying_) MockSY(underlying_) {}

    function transfer(address to, uint256 amount) public override(ERC20, IERC20) returns (bool) {
        require(amount != 0, "zero transfer rejected");
        return super.transfer(to, amount);
    }
}
