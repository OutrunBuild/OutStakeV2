// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

// L2 wstETH SY adapter. On L2, wstETH balance doesn't accrue staking rewards
// (rewards accrue on Ethereum mainnet). The exchange rate comes from an oracle
// that tracks what wstETH is worth on L1. Deposit/redeem are 1:1 with wstETH
// since wrapping happens at the L2 bridge level.

import {SYBaseUpgradeable} from "../../SYBaseUpgradeable.sol";
import {ArrayLib} from "../../../libraries/ArrayLib.sol";
import {IExchangeRateOracle} from "../../../libraries/oracle/interfaces/IExchangeRateOracle.sol";

contract OutrunL2WstETHSYUpgradeable is SYBaseUpgradeable {
    /// @custom:storage-location erc7201:outrun.storage.OutrunL2WstETHSY
    // forge-lint: disable-next-line(pascal-case-struct)
    struct OutrunL2WstETHSYStorage {
        // Oracle reports the current L1 wstETH exchange rate.
        // Needed because L2 wstETH balance is static — the oracle
        // makes the rate visible for position accounting.
        address exchangeRateOracle;
        // The underlying is stETH on Ethereum mainnet (not deployed on this L2).
        // Asset info describes what the SY ultimately represents.
        address underlyingAssetOnEthAddr;
        uint8 underlyingAssetOnEthDecimals;
    }

    // keccak256(abi.encode(uint256(keccak256("outrun.storage.OutrunL2WstETHSY")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant OUTRUN_L2_WST_ETH_SY_STORAGE_LOCATION =
        0x7e7baed09ce3e69f5f6da116459da34887eb64a288faa154ae38a8995cda0000;

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
        OutrunL2WstETHSYStorage storage $ = _getStorage();
        $.exchangeRateOracle = exchangeRateOracle_;
        $.underlyingAssetOnEthAddr = underlyingAssetOnEthAddr_;
        $.underlyingAssetOnEthDecimals = underlyingAssetOnEthDecimals_;
    }

    function _getStorage() private pure returns (OutrunL2WstETHSYStorage storage $) {
        // slither-disable-next-line assembly
        assembly {
            $.slot := OUTRUN_L2_WST_ETH_SY_STORAGE_LOCATION
        }
    }

    function exchangeRateOracle() public view returns (address) {
        return _getStorage().exchangeRateOracle;
    }

    function setExchangeRateOracle(address newOracle) external onlyOwner {
        if (newOracle == address(0)) revert SYZeroAddress();
        OutrunL2WstETHSYStorage storage $ = _getStorage();
        address oldOracle = $.exchangeRateOracle;
        $.exchangeRateOracle = newOracle;
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
        OutrunL2WstETHSYStorage storage $ = _getStorage();
        return (AssetType.TOKEN, $.underlyingAssetOnEthAddr, $.underlyingAssetOnEthDecimals);
    }
}
