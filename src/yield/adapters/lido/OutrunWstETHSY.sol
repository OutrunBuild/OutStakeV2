// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {IStETH} from "../../../integrations/lido/interfaces/IStETH.sol";
import {IWstETH} from "../../../integrations/lido/interfaces/IWstETH.sol";
import {ArrayLib} from "../../../libraries/ArrayLib.sol";
import {SYBase, IERC20Metadata} from "../../SYBase.sol";

contract OutrunWstETHSY is SYBase {
    address public immutable STETH;

    constructor(address _owner, address _stETH, address _wstETH)
        SYBase("SY Lido wstETH", "SY wstETH", _wstETH, _owner)
    {
        STETH = _stETH;
    }

    function _deposit(address tokenIn, uint256 amountDeposited) internal override returns (uint256 amountSharesOut) {
        if (tokenIn == NATIVE) {
            // Lido L1 uses submit(address) and address(0) denotes the no-referral path.
            uint256 stETHShareAmount = IStETH(STETH).submit{value: amountDeposited}(address(0));
            _safeApproveInf(STETH, yieldBearingToken);
            amountSharesOut = IWstETH(yieldBearingToken).wrap(IStETH(STETH).getPooledEthByShares(stETHShareAmount));
        } else if (tokenIn == STETH) {
            _safeApproveInf(STETH, yieldBearingToken);
            amountSharesOut = IWstETH(yieldBearingToken).wrap(amountDeposited);
        } else {
            amountSharesOut = amountDeposited;
        }
    }

    function _redeem(address receiver, address tokenOut, uint256 amountSharesToRedeem)
        internal
        override
        returns (uint256 amountTokenOut)
    {
        if (tokenOut == STETH) {
            amountTokenOut = IWstETH(yieldBearingToken).unwrap(amountSharesToRedeem);
            _transferOut(STETH, receiver, amountTokenOut);
        } else {
            _transferOut(yieldBearingToken, receiver, amountSharesToRedeem);
            amountTokenOut = amountSharesToRedeem;
        }
    }

    /**
     * @notice Returns the current stETH-per-share rate for this Lido SY.
     * @dev The rate is read directly from the configured wstETH wrapper.
     * @return res The current exchange rate between SY shares and stETH.
     */
    function exchangeRate() public view override returns (uint256 res) {
        return IWstETH(yieldBearingToken).stEthPerToken();
    }

    function _previewDeposit(address tokenIn, uint256 amountTokenToDeposit)
        internal
        view
        override
        returns (uint256 amountSharesOut)
    {
        if (tokenIn == NATIVE || tokenIn == STETH) {
            amountSharesOut = IStETH(STETH).getSharesByPooledEth(amountTokenToDeposit);
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
        if (tokenOut == STETH) {
            amountTokenOut = IStETH(STETH).getPooledEthByShares(amountSharesToRedeem);
        } else {
            amountTokenOut = amountSharesToRedeem;
        }
    }

    /**
     * @notice Returns the tokens accepted for deposits into this SY.
     * @dev Deposits can use native ETH, stETH, or the configured wstETH token directly.
     * @return res The supported deposit token list.
     */
    function getTokensIn() public view override returns (address[] memory res) {
        return ArrayLib.create(yieldBearingToken, NATIVE, STETH);
    }

    /**
     * @notice Returns the tokens redeemable from this SY.
     * @dev Redemptions can settle into either wstETH or unwrapped stETH.
     * @return res The supported redemption token list.
     */
    function getTokensOut() public view override returns (address[] memory res) {
        return ArrayLib.create(yieldBearingToken, STETH);
    }

    /**
     * @notice Returns whether `token` is accepted on deposit.
     * @dev Only native ETH, stETH, and the configured wstETH token are valid deposit inputs.
     * @param token The token to validate.
     * @return True when `token` is supported for deposits.
     */
    function isValidTokenIn(address token) public view override returns (bool) {
        return token == yieldBearingToken || token == NATIVE || token == STETH;
    }

    /**
     * @notice Returns whether `token` is accepted on redemption.
     * @dev Only stETH and the configured wstETH token are valid redemption outputs.
     * @param token The token to validate.
     * @return True when `token` is supported for redemptions.
     */
    function isValidTokenOut(address token) public view override returns (bool) {
        return token == yieldBearingToken || token == STETH;
    }

    /**
     * @notice Returns metadata describing the asset represented by this SY.
     * @dev The adapter reports stETH as the canonical asset backing the wrapped position.
     * @return assetType The asset classification used by the SY interface.
     * @return assetAddress The underlying asset address.
     * @return assetDecimals The decimals reported by stETH.
     */
    function assetInfo() external view returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        return (AssetType.TOKEN, STETH, IERC20Metadata(STETH).decimals());
    }
}
