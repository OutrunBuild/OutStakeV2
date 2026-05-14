// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {IMockAUSDC} from "../../support/MockAUSDC.sol";
import {ArrayLib} from "../../../src/libraries/ArrayLib.sol";
import {SYBaseUpgradeable} from "../../../src/yield/SYBaseUpgradeable.sol";

interface IMockExchangeRateOracle {
    function getExchangeRate() external view returns (uint256);
}

/**
 * @dev Just For Memeverse Genesis Test
 */
contract MockOutrunAUSDCSYUpgradeable is SYBaseUpgradeable {
    uint256 internal constant EXCHANGE_RATE_ONE = 1e18;

    /// @custom:storage-location erc7201:outrun.storage.MockOutrunAUSDCSY
    // forge-lint: disable-next-line(pascal-case-struct)
    struct MockOutrunAUSDCSYStorage {
        address mockUSDC;
        address oracle;
    }

    // keccak256(abi.encode(uint256(keccak256("outrun.storage.MockOutrunAUSDCSY")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant MOCK_OUTRUN_AUSDC_SY_STORAGE_LOCATION =
        0x9940b764f077542a31232cee433800d8404955802e94dc0fb857e7f79ae71100;

    function initialize(address owner_, address mockUSDC_, address aUSDC_, address oracle_) external initializer {
        require(mockUSDC_ != address(0) && oracle_ != address(0), SYZeroAddress());
        __SYBase_init("SY Aave aUSDC", "SY aUSDC", aUSDC_, owner_);

        MockOutrunAUSDCSYStorage storage $ = _getMockOutrunAUSDCSYStorage();
        $.mockUSDC = mockUSDC_;
        $.oracle = oracle_;
    }

    function _getMockOutrunAUSDCSYStorage() private pure returns (MockOutrunAUSDCSYStorage storage $) {
        // slither-disable-next-line assembly
        assembly {
            $.slot := MOCK_OUTRUN_AUSDC_SY_STORAGE_LOCATION
        }
    }

    function mockUSDC() public view returns (address) {
        return _getMockOutrunAUSDCSYStorage().mockUSDC;
    }

    function oracle() public view returns (address) {
        return _getMockOutrunAUSDCSYStorage().oracle;
    }

    function _deposit(address tokenIn, uint256 amountDeposited) internal override returns (uint256 amountSharesOut) {
        if (tokenIn == mockUSDC()) {
            address ybt = yieldBearingToken();
            _safeApproveInf(tokenIn, ybt);
            return IMockAUSDC(ybt).wrap(amountDeposited);
        }

        return amountDeposited;
    }

    function _redeem(address receiver, address tokenOut, uint256 amountSharesToRedeem)
        internal
        override
        returns (uint256 amountTokenOut)
    {
        if (tokenOut == mockUSDC()) {
            amountTokenOut = IMockAUSDC(yieldBearingToken()).unwrap(amountSharesToRedeem);
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
