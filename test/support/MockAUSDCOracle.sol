// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @dev Mock aUSDC Oracle
 */
contract MockAUSDCOracle is Ownable {
    error InvalidOracleAnswer();

    uint8 public constant DECIMALS = 18;
    uint8 public constant RAW_DECIMALS = 6;

    int256 public latestAnswer;

    constructor(address _owner) Ownable(_owner) {
        latestAnswer = 1000000;
    }

    function getExchangeRate() external view returns (uint256) {
        if (latestAnswer <= 0) revert InvalidOracleAnswer();
        // latestAnswer is checked to be strictly positive before converting to uint256.
        // forge-lint: disable-next-line(unsafe-typecast)
        return (uint256(latestAnswer) * 10 ** DECIMALS) / 10 ** RAW_DECIMALS;
    }

    function setLatestAnswer(int256 _latestAnswer) external onlyOwner {
        latestAnswer = _latestAnswer;
    }
}
