// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {SYBase} from "../../SYBase.sol";
import {ArrayLib} from "../../../libraries/ArrayLib.sol";

contract OutrunStakedUSDeSY is SYBase {
    address public immutable USDE;

    constructor(address _owner, address _USDe, address _sUSDe) SYBase("SY Ethena sUSDe", "SY sUSDe", _sUSDe, _owner) {
        USDE = _USDe;
    }

    function _deposit(address tokenIn, uint256 amountDeposited) internal override returns (uint256 amountSharesOut) {
        if (tokenIn == USDE) {
            _safeApproveInf(USDE, yieldBearingToken);
            amountSharesOut = IERC4626(yieldBearingToken).deposit(amountDeposited, address(this));
        } else {
            amountSharesOut = amountDeposited;
        }
    }

    function _redeem(
        address receiver,
        address,
        /*tokenOut*/
        uint256 amountSharesToRedeem
    )
        internal
        override
        returns (
            uint256 /*amountTokenOut*/
        )
    {
        _transferOut(yieldBearingToken, receiver, amountSharesToRedeem);
        return amountSharesToRedeem;
    }

    /**
     * @notice Returns the current asset-per-share rate for this Ethena SY.
     * @dev The rate is sourced from the ERC4626 vault's assets-per-share conversion for `1 ether`.
     * @return res The current exchange rate between shares and USDE-denominated assets.
     */
    function exchangeRate() public view override returns (uint256 res) {
        return IERC4626(yieldBearingToken).convertToAssets(1 ether);
    }

    function _previewDeposit(address tokenIn, uint256 amountTokenToDeposit)
        internal
        view
        override
        returns (uint256 amountSharesOut)
    {
        if (tokenIn == USDE) {
            amountSharesOut = IERC4626(yieldBearingToken).previewDeposit(amountTokenToDeposit);
        } else {
            amountSharesOut = amountTokenToDeposit;
        }
    }

    function _previewRedeem(
        address,
        /*tokenOut*/
        uint256 amountSharesToRedeem
    )
        internal
        pure
        override
        returns (
            uint256 /*amountTokenOut*/
        )
    {
        return amountSharesToRedeem;
    }

    /**
     * @notice Returns the tokens accepted for deposits into this SY.
     * @dev Deposits can use either the yield-bearing vault token directly or the underlying USDE asset.
     * @return res The supported deposit token list.
     */
    function getTokensIn() public view override returns (address[] memory res) {
        return ArrayLib.create(yieldBearingToken, USDE);
    }

    /**
     * @notice Returns the tokens redeemable from this SY.
     * @dev This adapter only redeems into the yield-bearing vault token.
     * @return res The supported redemption token list.
     */
    function getTokensOut() public view override returns (address[] memory res) {
        return ArrayLib.create(yieldBearingToken);
    }

    /**
     * @notice Returns whether `token` is accepted on deposit.
     * @dev Deposits are limited to the configured vault token and USDE.
     * @param token The token to validate.
     * @return True when `token` is supported for deposits.
     */
    function isValidTokenIn(address token) public view override returns (bool) {
        return token == yieldBearingToken || token == USDE;
    }

    /**
     * @notice Returns whether `token` is accepted on redemption.
     * @dev Redemptions from this adapter are only exposed as the vault token itself.
     * @param token The token to validate.
     * @return True when `token` is supported for redemptions.
     */
    function isValidTokenOut(address token) public view override returns (bool) {
        return token == yieldBearingToken;
    }

    /**
     * @notice Returns metadata describing the asset represented by this SY.
     * @dev The adapter reports USDE as the canonical asset with 18 decimals.
     * @return assetType The asset classification used by the SY interface.
     * @return assetAddress The underlying asset address.
     * @return assetDecimals The decimals used for the underlying asset.
     */
    function assetInfo() external view returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        return (AssetType.TOKEN, USDE, 18);
    }
}
