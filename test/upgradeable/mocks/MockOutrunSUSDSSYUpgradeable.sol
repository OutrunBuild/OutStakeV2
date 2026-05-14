// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {IMockSUSDS} from "../../support/MockSUSDS.sol";
import {ArrayLib} from "../../../src/libraries/ArrayLib.sol";
import {SYBaseUpgradeable} from "../../../src/yield/SYBaseUpgradeable.sol";
import {IMockExchangeRateOracle} from "./MockOutrunAUSDCSYUpgradeable.sol";

/**
 * @dev Just For Memeverse Genesis Test
 */
contract MockOutrunSUSDSSYUpgradeable is SYBaseUpgradeable {
    uint256 internal constant EXCHANGE_RATE_ONE = 1e18;

    /// @custom:storage-location erc7201:outrun.storage.MockOutrunSUSDSSY
    // forge-lint: disable-next-line(pascal-case-struct)
    struct MockOutrunSUSDSSYStorage {
        address mockUSDC;
        address oracle;
    }

    // keccak256(abi.encode(uint256(keccak256("outrun.storage.MockOutrunSUSDSSY")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant MOCK_OUTRUN_SUSDS_SY_STORAGE_LOCATION =
        0x6d98bb15a5abb859035ff0804bf4105e99357788f976703c6fe7f739730c4900;

    function initialize(address owner_, address mockUSDC_, address sUSDS_, address oracle_) external initializer {
        require(mockUSDC_ != address(0) && oracle_ != address(0), SYZeroAddress());
        __SYBase_init("SY Sky sUSDS", "SY sUSDS", sUSDS_, owner_);

        MockOutrunSUSDSSYStorage storage $ = _getMockOutrunSUSDSSYStorage();
        $.mockUSDC = mockUSDC_;
        $.oracle = oracle_;
    }

    function _getMockOutrunSUSDSSYStorage() private pure returns (MockOutrunSUSDSSYStorage storage $) {
        // slither-disable-next-line assembly
        assembly {
            $.slot := MOCK_OUTRUN_SUSDS_SY_STORAGE_LOCATION
        }
    }

    function mockUSDC() public view returns (address) {
        return _getMockOutrunSUSDSSYStorage().mockUSDC;
    }

    function oracle() public view returns (address) {
        return _getMockOutrunSUSDSSYStorage().oracle;
    }

    function _deposit(address tokenIn, uint256 amountDeposited) internal override returns (uint256 amountSharesOut) {
        if (tokenIn == mockUSDC()) {
            address ybt = yieldBearingToken();
            _safeApproveInf(tokenIn, ybt);
            return IMockSUSDS(ybt).wrap(amountDeposited);
        }

        return amountDeposited;
    }

    function _redeem(address receiver, address tokenOut, uint256 amountSharesToRedeem)
        internal
        override
        returns (uint256 amountTokenOut)
    {
        if (tokenOut == mockUSDC()) {
            amountTokenOut = IMockSUSDS(yieldBearingToken()).unwrap(amountSharesToRedeem);
            _transferOut(tokenOut, receiver, amountTokenOut);
            return amountTokenOut;
        }

        _transferOut(tokenOut, receiver, amountSharesToRedeem);
        return amountSharesToRedeem;
    }

    function exchangeRate() public view override returns (uint256 res) {
        try IMockExchangeRateOracle(oracle()).getExchangeRate() returns (uint256 rate) {
            if (rate != 0) return rate;
        } catch {}

        return EXCHANGE_RATE_ONE;
    }

    function _previewDeposit(address, uint256 amountTokenToDeposit) internal pure override returns (uint256) {
        return amountTokenToDeposit;
    }

    function _previewRedeem(address, uint256 amountSharesToRedeem) internal pure override returns (uint256) {
        return amountSharesToRedeem;
    }

    function getTokensIn() public view override returns (address[] memory) {
        return ArrayLib.create(mockUSDC(), yieldBearingToken());
    }

    function getTokensOut() public view override returns (address[] memory) {
        return ArrayLib.create(mockUSDC(), yieldBearingToken());
    }

    function isValidTokenIn(address token) public view override returns (bool) {
        return token == mockUSDC() || token == yieldBearingToken();
    }

    function isValidTokenOut(address token) public view override returns (bool) {
        return token == mockUSDC() || token == yieldBearingToken();
    }

    function assetInfo() external view returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        return (AssetType.TOKEN, mockUSDC(), 18);
    }
}
