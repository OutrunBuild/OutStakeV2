// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {SYBaseUpgradeable} from "./SYBaseUpgradeable.sol";
import {ArrayLib} from "../libraries/ArrayLib.sol";
import {IExchangeRateOracle} from "../libraries/oracle/interfaces/IExchangeRateOracle.sol";

contract OutrunL2StakedTokenSYUpgradeable is SYBaseUpgradeable {
    /// @custom:storage-location erc7201:outrun.storage.OutrunL2StakedTokenSY
    // forge-lint: disable-next-line(pascal-case-struct)
    struct OutrunL2StakedTokenSYStorage {
        address exchangeRateOracle;
        address underlyingAssetOnEthAddr;
        uint8 underlyingAssetOnEthDecimals;
    }

    // keccak256(abi.encode(uint256(keccak256("outrun.storage.OutrunL2StakedTokenSY")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant OUTRUN_L2_STAKED_TOKEN_SY_STORAGE_LOCATION =
        0xc47406d15de2f1a441454f67ed7478fdea0ecc904b6c2e82cf019a344492a300;

    event SetExchangeRateOracle(address indexed oldOracle, address indexed newOracle);

    function initialize(
        string calldata name_,
        string calldata symbol_,
        address owner_,
        address token_,
        address exchangeRateOracle_,
        address underlyingAssetOnEthAddr_,
        uint8 underlyingAssetOnEthDecimals_
    ) external initializer {
        __SYBase_init(name_, symbol_, token_, owner_);
        _initializeL2(exchangeRateOracle_, underlyingAssetOnEthAddr_, underlyingAssetOnEthDecimals_);
    }

    function _getStorage() private pure returns (OutrunL2StakedTokenSYStorage storage $) {
        // slither-disable-next-line assembly
        assembly {
            $.slot := OUTRUN_L2_STAKED_TOKEN_SY_STORAGE_LOCATION
        }
    }

    function _initializeL2(address exchangeRateOracle_, address underlyingAssetOnEthAddr_, uint8 decimals_) internal {
        if (exchangeRateOracle_ == address(0) || underlyingAssetOnEthAddr_ == address(0)) revert SYZeroAddress();
        OutrunL2StakedTokenSYStorage storage $ = _getStorage();
        $.exchangeRateOracle = exchangeRateOracle_;
        $.underlyingAssetOnEthAddr = underlyingAssetOnEthAddr_;
        $.underlyingAssetOnEthDecimals = decimals_;
    }

    function exchangeRateOracle() public view returns (address) {
        return _getStorage().exchangeRateOracle;
    }

    function setExchangeRateOracle(address newOracle) external onlyOwner {
        if (newOracle == address(0)) revert SYZeroAddress();
        OutrunL2StakedTokenSYStorage storage $ = _getStorage();
        address oldOracle = $.exchangeRateOracle;
        $.exchangeRateOracle = newOracle;
        emit SetExchangeRateOracle(oldOracle, newOracle);
    }

    function _deposit(address, uint256 amountDeposited) internal pure override returns (uint256) {
        return amountDeposited;
    }

    function _redeem(address receiver, address tokenOut, uint256 amountSharesToRedeem)
        internal
        override
        returns (uint256)
    {
        _transferOut(tokenOut, receiver, amountSharesToRedeem);
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
        OutrunL2StakedTokenSYStorage storage $ = _getStorage();
        return (AssetType.TOKEN, $.underlyingAssetOnEthAddr, $.underlyingAssetOnEthDecimals);
    }
}
