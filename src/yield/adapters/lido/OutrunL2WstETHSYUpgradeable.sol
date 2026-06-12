// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.35;

// L2 wstETH SY adapter. On L2, wstETH balance doesn't accrue staking rewards
// (rewards accrue on Ethereum mainnet). The exchange rate comes from an oracle
// that tracks what wstETH is worth on L1. Deposit/redeem are 1:1 with wstETH
// since wrapping happens at the L2 bridge level.

import {SYBaseUpgradeable} from "../../SYBaseUpgradeable.sol";
import {ArrayLib} from "../../../libraries/ArrayLib.sol";
import {IExchangeRateOracle} from "../../../libraries/oracle/interfaces/IExchangeRateOracle.sol";

contract OutrunL2WstETHSYUpgradeable layout at erc7201("outrun.storage.OutrunL2WstETHSY") is SYBaseUpgradeable {
    struct OutrunL2WstETHSYStorage {
        // Oracle reports the current L1 wstETH exchange rate.
        // Needed because L2 wstETH balance is static — the oracle
        // makes the rate visible for position accounting.
        // Production Lido L2 wstETH/stETH rate adapters should use maxStaleness = 2 days
        // and enable the L2 sequencer uptime feed with a post-recovery grace period.
        // Evidence: Lido cross-chain token guide says stETH rate data should not be outdated by more than 2 days.
        // https://docs.lido.fi/token-guides/cross-chain-tokens-guide/
        address exchangeRateOracle;
        // The underlying is stETH on Ethereum mainnet (not deployed on this L2).
        // Asset info describes what the SY ultimately represents.
        address underlyingAssetOnEthAddr;
        uint8 underlyingAssetOnEthDecimals;
    }
    OutrunL2WstETHSYStorage private outrunL2WstETHSYStorage;

    event SetExchangeRateOracle(address indexed oldOracle, address indexed newOracle);

    function initialize(
        address owner_,
        address wstETH_,
        address exchangeRateOracle_,
        address underlyingAssetOnEthAddr_,
        uint8 underlyingAssetOnEthDecimals_
    ) external initializer {
        if (exchangeRateOracle_ == address(0) || underlyingAssetOnEthAddr_ == address(0)) revert SYZeroAddress();
        __SYBase_init("SY Lido wstETH", "SY wstETH", wstETH_, owner_);
        outrunL2WstETHSYStorage.exchangeRateOracle = exchangeRateOracle_;
        outrunL2WstETHSYStorage.underlyingAssetOnEthAddr = underlyingAssetOnEthAddr_;
        outrunL2WstETHSYStorage.underlyingAssetOnEthDecimals = underlyingAssetOnEthDecimals_;
    }

    function exchangeRateOracle() public view returns (address) {
        return outrunL2WstETHSYStorage.exchangeRateOracle;
    }

    function setExchangeRateOracle(address newOracle) external onlyOwner {
        if (newOracle == address(0)) revert SYZeroAddress();
        address oldOracle = outrunL2WstETHSYStorage.exchangeRateOracle;
        outrunL2WstETHSYStorage.exchangeRateOracle = newOracle;
        emit SetExchangeRateOracle(oldOracle, newOracle);
    }

    // 1:1 conversion — the yield accrual is external (tracked by oracle),
    // so no wrapping math happens here.
    function _deposit(address, uint256 amountDeposited) internal pure override returns (uint256) {
        return amountDeposited;
    }

    // 1:1 conversion — the yield accrual is external (tracked by oracle),
    // so no wrapping math happens here.
    function _redeem(address receiver, address, uint256 amountSharesToRedeem) internal override returns (uint256) {
        _transferOut(yieldBearingToken(), receiver, amountSharesToRedeem);
        return amountSharesToRedeem;
    }

    function exchangeRate() public view override returns (uint256) {
        return IExchangeRateOracle(exchangeRateOracle()).getExchangeRate();
    }

    function _previewDeposit(address, uint256 amountTokenToDeposit) internal pure override returns (uint256) {
        return amountTokenToDeposit;
    }

    function _previewRedeem(address, uint256 amountSharesToRedeem) internal pure override returns (uint256) {
        return amountSharesToRedeem;
    }

    function getTokensIn() public view override returns (address[] memory res) {
        return ArrayLib.create(yieldBearingToken());
    }

    function getTokensOut() public view override returns (address[] memory res) {
        return ArrayLib.create(yieldBearingToken());
    }

    function isValidTokenIn(address token) public view override returns (bool) {
        return token == yieldBearingToken();
    }

    function isValidTokenOut(address token) public view override returns (bool) {
        return token == yieldBearingToken();
    }

    function assetInfo() external view returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        return (
            AssetType.TOKEN,
            outrunL2WstETHSYStorage.underlyingAssetOnEthAddr,
            outrunL2WstETHSYStorage.underlyingAssetOnEthDecimals
        );
    }
}
