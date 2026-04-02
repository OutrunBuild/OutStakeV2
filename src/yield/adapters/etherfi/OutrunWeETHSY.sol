// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {SYBase} from "../../SYBase.sol";
import {ArrayLib} from "../../../libraries/ArrayLib.sol";
import {IWeETH} from "../../../integrations/etherfi/interfaces/IWeETH.sol";
import {ILiquidityPool} from "../../../integrations/etherfi/interfaces/ILiquidityPool.sol";
import {IDepositAdapter} from "../../../integrations/etherfi/interfaces/IDepositAdapter.sol";

contract OutrunWeETHSY is SYBase {
    address public immutable EETH;
    address public immutable DEPOSIT_ADAPTER;
    address public immutable LIQUIDITY_POOL;

    constructor(address _owner, address _eETH, address _weETH, address _depositAdapter, address _liquidityPool)
        SYBase("SY Etherfi weETH", "SY weETH", _weETH, _owner)
    {
        EETH = _eETH;
        DEPOSIT_ADAPTER = _depositAdapter;
        LIQUIDITY_POOL = _liquidityPool;
    }

    function _deposit(address tokenIn, uint256 amountDeposited) internal override returns (uint256 amountSharesOut) {
        if (tokenIn == NATIVE) {
            amountSharesOut = IDepositAdapter(DEPOSIT_ADAPTER).depositETHForWeETH{value: amountDeposited}(address(0));
        } else if (tokenIn == EETH) {
            _safeApproveInf(EETH, yieldBearingToken);
            amountSharesOut = IWeETH(yieldBearingToken).wrap(amountDeposited);
        } else {
            amountSharesOut = amountDeposited;
        }
    }

    function _redeem(address receiver, address tokenOut, uint256 amountSharesToRedeem)
        internal
        override
        returns (uint256 amountTokenOut)
    {
        if (tokenOut == EETH) {
            amountTokenOut = IWeETH(yieldBearingToken).unwrap(amountSharesToRedeem);
            _transferOut(EETH, receiver, amountTokenOut);
        } else {
            amountTokenOut = amountSharesToRedeem;
            _transferOut(yieldBearingToken, receiver, amountSharesToRedeem);
        }
    }

    /// @notice Returns the current eETH-per-weETH exchange rate from the liquidity pool.
    /// @dev Reads the amount of eETH represented by one weETH share.
    /// @return res The current exchange rate scaled to 18 decimals.
    function exchangeRate() public view override returns (uint256 res) {
        return ILiquidityPool(LIQUIDITY_POOL).amountForShare(1 ether);
    }

    function _previewDeposit(address tokenIn, uint256 amountTokenToDeposit)
        internal
        view
        override
        returns (uint256 amountSharesOut)
    {
        if (tokenIn == NATIVE) {
            uint256 eETHAmount = ILiquidityPool(LIQUIDITY_POOL)
                .amountForShare(ILiquidityPool(LIQUIDITY_POOL).sharesForAmount(amountTokenToDeposit));
            amountSharesOut = ILiquidityPool(LIQUIDITY_POOL).sharesForAmount(eETHAmount);
        } else if (tokenIn == EETH) {
            amountSharesOut = ILiquidityPool(LIQUIDITY_POOL).sharesForAmount(amountTokenToDeposit);
        } else {
            amountSharesOut = amountTokenToDeposit;
        }
    }

    function _previewRedeem(address tokenOut, uint256 amountSharesToRedeem)
        internal
        view
        override
        returns (uint256 amountTokenOut)
    {
        if (tokenOut == EETH) {
            amountTokenOut = ILiquidityPool(LIQUIDITY_POOL).amountForShare(amountSharesToRedeem);
        } else {
            amountTokenOut = amountSharesToRedeem;
        }
    }

    /// @notice Lists supported input tokens.
    /// @dev Deposits may be supplied as native ETH, eETH, or weETH.
    /// @return res The supported deposit token list.
    function getTokensIn() public view override returns (address[] memory res) {
        return ArrayLib.create(NATIVE, EETH, yieldBearingToken);
    }

    /// @notice Lists supported output tokens.
    /// @dev Redemptions may be received as eETH or weETH.
    /// @return res The supported redemption token list.
    function getTokensOut() public view override returns (address[] memory res) {
        return ArrayLib.create(EETH, yieldBearingToken);
    }

    /// @notice Checks whether `token` can be deposited into this SY.
    /// @dev Accepts native ETH, eETH, and the wrapped yield-bearing token.
    /// @param token The token to validate.
    /// @return Whether the token is supported as input.
    function isValidTokenIn(address token) public view override returns (bool) {
        return token == NATIVE || token == EETH || token == yieldBearingToken;
    }

    /// @notice Checks whether `token` can be redeemed from this SY.
    /// @dev Redemption supports eETH and weETH outputs.
    /// @param token The token to validate.
    /// @return Whether the token is supported as output.
    function isValidTokenOut(address token) public view override returns (bool) {
        return token == EETH || token == yieldBearingToken;
    }

    /// @notice Returns canonical asset metadata for integrations.
    /// @dev The base asset exposed by this SY is native ETH with 18 decimals.
    /// @return assetType The asset type for the underlying asset.
    /// @return assetAddress The canonical underlying asset address.
    /// @return assetDecimals The canonical underlying asset decimals.
    function assetInfo() external pure returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        return (AssetType.TOKEN, NATIVE, 18);
    }
}
