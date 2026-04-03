// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {SYBase} from "../../SYBase.sol";
import {ArrayLib} from "../../../libraries/ArrayLib.sol";
import {IPSM3} from "../../../integrations/sky/interfaces/IPSM3.sol";

contract OutrunL2StakedUsdsSY is SYBase {
    address public immutable USDC;
    address public immutable USDS;
    address public immutable PSM3;

    constructor(address _owner, address _USDC, address _USDS, address _sUSDS, address _PSM3)
        SYBase("SY Sky sUSDS", "SY sUSDS", _sUSDS, _owner)
    {
        USDC = _USDC;
        USDS = _USDS;
        PSM3 = _PSM3;
    }

    function _deposit(address tokenIn, uint256 amountDeposited) internal override returns (uint256 amountSharesOut) {
        if (tokenIn == yieldBearingToken) {
            amountSharesOut = amountDeposited;
        } else {
            _safeApproveInf(tokenIn, PSM3);
            amountSharesOut = IPSM3(PSM3).swapExactIn(tokenIn, yieldBearingToken, amountDeposited, 0, address(this), 0);
        }
    }

    function _redeem(address receiver, address tokenOut, uint256 amountSharesToRedeem)
        internal
        override
        returns (uint256 amountTokenOut)
    {
        if (tokenOut == yieldBearingToken) {
            _transferOut(yieldBearingToken, receiver, amountSharesToRedeem);
            amountTokenOut = amountSharesToRedeem;
        } else {
            _safeApproveInf(yieldBearingToken, PSM3);
            amountTokenOut = IPSM3(PSM3).swapExactIn(yieldBearingToken, tokenOut, amountSharesToRedeem, 0, receiver, 0);
        }
    }

    /**
     * @notice Returns the current USDS-per-share rate for this Sky L2 SY.
     * @dev The rate is derived from the PSM quote for swapping one share unit into USDS.
     * @return res The current exchange rate between shares and USDS.
     */
    function exchangeRate() public view override returns (uint256 res) {
        return IPSM3(PSM3).previewSwapExactIn(yieldBearingToken, USDS, 1 ether);
    }

    function _previewDeposit(address tokenIn, uint256 amountTokenToDeposit)
        internal
        view
        override
        returns (uint256 amountSharesOut)
    {
        if (tokenIn == yieldBearingToken) {
            amountSharesOut = amountTokenToDeposit;
        } else {
            amountSharesOut = IPSM3(PSM3).previewSwapExactIn(tokenIn, yieldBearingToken, amountTokenToDeposit);
        }
    }

    function _previewRedeem(address tokenOut, uint256 amountSharesToRedeem)
        internal
        view
        override
        returns (uint256 amountTokenOut)
    {
        if (tokenOut == yieldBearingToken) {
            amountTokenOut = amountSharesToRedeem;
        } else {
            amountTokenOut = IPSM3(PSM3).previewSwapExactIn(yieldBearingToken, tokenOut, amountSharesToRedeem);
        }
    }

    /**
     * @notice Returns the tokens accepted for deposits into this SY.
     * @dev Deposits can use USDC, USDS, or the configured yield-bearing token.
     * @return res The supported deposit token list.
     */
    function getTokensIn() public view override returns (address[] memory res) {
        return ArrayLib.create(USDC, USDS, yieldBearingToken);
    }

    /**
     * @notice Returns the tokens redeemable from this SY.
     * @dev Redemptions can settle into USDC, USDS, or the configured yield-bearing token.
     * @return res The supported redemption token list.
     */
    function getTokensOut() public view override returns (address[] memory res) {
        return ArrayLib.create(USDC, USDS, yieldBearingToken);
    }

    /**
     * @notice Returns whether `token` is accepted on deposit.
     * @dev Valid deposit tokens are USDC, USDS, and the configured yield-bearing token.
     * @param token The token to validate.
     * @return True when `token` is supported for deposits.
     */
    function isValidTokenIn(address token) public view override returns (bool) {
        return token == USDC || token == USDS || token == yieldBearingToken;
    }

    /**
     * @notice Returns whether `token` is accepted on redemption.
     * @dev Valid redemption tokens are USDC, USDS, and the configured yield-bearing token.
     * @param token The token to validate.
     * @return True when `token` is supported for redemptions.
     */
    function isValidTokenOut(address token) public view override returns (bool) {
        return token == USDC || token == USDS || token == yieldBearingToken;
    }

    /**
     * @notice Returns metadata describing the asset represented by this SY.
     * @dev The adapter reports USDS as the canonical asset with 18 decimals.
     * @return assetType The asset classification used by the SY interface.
     * @return assetAddress The underlying asset address.
     * @return assetDecimals The decimals used for the underlying asset.
     */
    function assetInfo() external view returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        return (AssetType.TOKEN, USDS, 18);
    }
}
