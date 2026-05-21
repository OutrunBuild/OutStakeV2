// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

// L2 SY adapter for Sky sUSDS. Uses PSM3 (Peg Stability Module) to swap between USDC, USDS, and sUSDS.
// Deposit paths: USDC → swap to sUSDS via PSM3, USDS → swap to sUSDS via PSM3, or sUSDS directly.
// Exchange rate from PSM3.previewSwapExactIn(sUSDS→USDS).

import {SYBaseUpgradeable} from "../../SYBaseUpgradeable.sol";
import {ArrayLib} from "../../../libraries/ArrayLib.sol";
import {IPSM3} from "../../../integrations/sky/interfaces/IPSM3.sol";

contract OutrunL2StakedUsdsSYUpgradeable is SYBaseUpgradeable {
    /// @custom:storage-location erc7201:outrun.storage.OutrunL2StakedUsdsSY
    // forge-lint: disable-next-line(pascal-case-struct)
    struct OutrunL2StakedUsdsSYStorage {
        address USDC;
        address USDS;
        address PSM3;
    }

    // keccak256(abi.encode(uint256(keccak256("outrun.storage.OutrunL2StakedUsdsSY")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant OUTRUN_L2_STAKED_USDS_SY_STORAGE_LOCATION =
        0x87ae3998ef315b555888805db0bb7dcff6c26c66153e8971d42ff237c1174500;

    function initialize(address owner_, address USDC_, address USDS_, address sUSDS_, address PSM3_)
        external
        initializer
    {
        if (USDC_ == address(0) || USDS_ == address(0) || PSM3_ == address(0)) revert SYZeroAddress();
        __SYBase_init("SY Sky sUSDS", "SY sUSDS", sUSDS_, owner_);
        OutrunL2StakedUsdsSYStorage storage $ = _getStorage();
        $.USDC = USDC_;
        $.USDS = USDS_;
        $.PSM3 = PSM3_;
    }

    function _getStorage() private pure returns (OutrunL2StakedUsdsSYStorage storage $) {
        // slither-disable-next-line assembly
        assembly {
            $.slot := OUTRUN_L2_STAKED_USDS_SY_STORAGE_LOCATION
        }
    }

    function USDC() public view returns (address) {
        // Stablecoin input (USDC on L2)
        return _getStorage().USDC;
    }

    function USDS() public view returns (address) {
        // Sky's native stablecoin (also on L2 via bridge)
        return _getStorage().USDS;
    }

    function PSM3() public view returns (address) {
        // Peg Stability Module that handles swaps between USDC, USDS, and sUSDS
        return _getStorage().PSM3;
    }

    function _deposit(address tokenIn, uint256 amountDeposited) internal override returns (uint256 amountSharesOut) {
        address _yieldBearingToken = yieldBearingToken();
        // Deposit: if depositing sUSDS directly, 1:1. Otherwise, swap the input token to sUSDS via PSM3 at the current pool rate.
        if (tokenIn == _yieldBearingToken) {
            amountSharesOut = amountDeposited;
        } else {
            address _psm = PSM3();
            _safeApproveInf(tokenIn, _psm);
            amountSharesOut = IPSM3(_psm).swapExactIn(tokenIn, _yieldBearingToken, amountDeposited, 0, address(this), 0);
        }
    }

    function _redeem(address receiver, address tokenOut, uint256 amountSharesToRedeem)
        internal
        override
        returns (uint256 amountTokenOut)
    {
        address _yieldBearingToken = yieldBearingToken();
        // Redeem: if tokenOut is sUSDS, transfer directly. Otherwise, swap sUSDS to tokenOut via PSM3.
        if (tokenOut == _yieldBearingToken) {
            _transferOut(_yieldBearingToken, receiver, amountSharesToRedeem);
            amountTokenOut = amountSharesToRedeem;
        } else {
            address _psm = PSM3();
            _safeApproveInf(_yieldBearingToken, _psm);
            amountTokenOut = IPSM3(_psm).swapExactIn(_yieldBearingToken, tokenOut, amountSharesToRedeem, 0, receiver, 0);
        }
    }

    function exchangeRate() public view override returns (uint256 res) {
        // PSM3 previewSwapExactIn(sUSDS→USDS, 1 ether) gives the current exchange rate.
        // PSM3 maintains a USDS/USDC peg, so this rate reflects the sUSDS savings rate multiplied by any PSM3 pool imbalance.
        return IPSM3(PSM3()).previewSwapExactIn(yieldBearingToken(), USDS(), 1 ether);
    }

    function _previewDeposit(address tokenIn, uint256 amountTokenToDeposit) internal view override returns (uint256) {
        // sUSDS deposits are already shares; USDC/USDS deposits are quoted through PSM3.
        if (tokenIn == yieldBearingToken()) return amountTokenToDeposit;
        return IPSM3(PSM3()).previewSwapExactIn(tokenIn, yieldBearingToken(), amountTokenToDeposit);
    }

    function _previewRedeem(address tokenOut, uint256 amountSharesToRedeem) internal view override returns (uint256) {
        // Redeeming to sUSDS is 1:1; redeeming to USDC/USDS is quoted through PSM3.
        if (tokenOut == yieldBearingToken()) return amountSharesToRedeem;
        return IPSM3(PSM3()).previewSwapExactIn(yieldBearingToken(), tokenOut, amountSharesToRedeem);
    }

    function getTokensIn() public view override returns (address[] memory res) {
        return ArrayLib.create(USDC(), USDS(), yieldBearingToken());
    }

    function getTokensOut() public view override returns (address[] memory res) {
        return ArrayLib.create(USDC(), USDS(), yieldBearingToken());
    }

    function isValidTokenIn(address token) public view override returns (bool) {
        return token == USDC() || token == USDS() || token == yieldBearingToken();
    }

    function isValidTokenOut(address token) public view override returns (bool) {
        return token == USDC() || token == USDS() || token == yieldBearingToken();
    }

    function assetInfo() external view returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        return (AssetType.TOKEN, USDS(), 18);
    }
}
