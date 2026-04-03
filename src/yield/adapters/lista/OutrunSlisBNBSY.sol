// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {SYBase} from "../../SYBase.sol";
import {ArrayLib} from "../../../libraries/ArrayLib.sol";
import {ISlisBNBProvider} from "../../../integrations/lista/interfaces/ISlisBNBProvider.sol";
import {IListaBNBStakeManager} from "../../../integrations/lista/interfaces/IListaBNBStakeManager.sol";

contract OutrunSlisBNBSY is SYBase {
    IListaBNBStakeManager public immutable listaBNBStakeManager;
    ISlisBNBProvider public immutable slisBNBProvider;
    address public delegateTo;

    event UpdateDelegateTo(address oldDelegateTo, address indexed newDelegateTo);

    constructor(
        address _owner,
        address _slisBNB,
        address _delegateTo,
        IListaBNBStakeManager _stakeManager,
        ISlisBNBProvider _slisBNBProvider
    ) SYBase("SY Lista slisBNB", "SY slisBNB", _slisBNB, _owner) {
        delegateTo = _delegateTo;
        listaBNBStakeManager = _stakeManager;
        slisBNBProvider = _slisBNBProvider;
    }

    /**
     * @notice Updates the delegatee used for future provided slisBNB.
     * @dev Existing provided balance is released and re-provided so the full current supply follows the new delegatee.
     * @param _delegateTo The new delegatee address.
     */
    function updateDelegateTo(address _delegateTo) external onlyOwner {
        uint256 _totalSupply = totalSupply;
        slisBNBProvider.release(address(this), _totalSupply);
        _safeApproveInf(yieldBearingToken, address(slisBNBProvider));
        slisBNBProvider.provide(_totalSupply, _delegateTo);

        address oldDelegateTo = delegateTo;
        delegateTo = _delegateTo;

        emit UpdateDelegateTo(oldDelegateTo, _delegateTo);
    }

    function _deposit(address tokenIn, uint256 amountDeposited) internal override returns (uint256 amountSharesOut) {
        if (tokenIn == NATIVE) {
            listaBNBStakeManager.deposit{value: amountDeposited}();
            amountSharesOut = listaBNBStakeManager.convertBnbToSnBnb(amountDeposited);
        } else {
            amountSharesOut = amountDeposited;
        }

        _safeApproveInf(yieldBearingToken, address(slisBNBProvider));
        slisBNBProvider.provide(amountSharesOut, delegateTo);
    }

    function _redeem(
        address receiver,
        address,
        /*tokenOut*/
        uint256 amountSharesToRedeem
    )
        internal
        override
        returns (uint256)
    {
        slisBNBProvider.release(receiver, amountSharesToRedeem);
        return amountSharesToRedeem;
    }

    /**
     * @notice Returns the current BNB-per-share rate for this Lista SY.
     * @dev The rate is sourced from the Lista stake manager's slisBNB-to-BNB conversion.
     * @return res The current exchange rate between shares and native BNB.
     */
    function exchangeRate() public view override returns (uint256 res) {
        return listaBNBStakeManager.convertSnBnbToBnb(1 ether);
    }

    function _previewDeposit(address tokenIn, uint256 amountTokenToDeposit)
        internal
        view
        override
        returns (uint256 amountSharesOut)
    {
        if (tokenIn == NATIVE) {
            amountSharesOut = listaBNBStakeManager.convertBnbToSnBnb(amountTokenToDeposit);
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
     * @dev Deposits can use native BNB or the configured yield-bearing slisBNB token.
     * @return res The supported deposit token list.
     */
    function getTokensIn() public view override returns (address[] memory res) {
        return ArrayLib.create(yieldBearingToken, NATIVE);
    }

    /**
     * @notice Returns the tokens redeemable from this SY.
     * @dev This adapter redeems into the configured yield-bearing slisBNB token path.
     * @return res The supported redemption token list.
     */
    function getTokensOut() public view override returns (address[] memory res) {
        return ArrayLib.create(yieldBearingToken);
    }

    /**
     * @notice Returns whether `token` is accepted on deposit.
     * @dev Deposits are limited to native BNB and the configured slisBNB token.
     * @param token The token to validate.
     * @return True when `token` is supported for deposits.
     */
    function isValidTokenIn(address token) public view override returns (bool) {
        return token == yieldBearingToken || token == NATIVE;
    }

    /**
     * @notice Returns whether `token` is accepted on redemption.
     * @dev Redemptions from this adapter only expose the configured slisBNB token.
     * @param token The token to validate.
     * @return True when `token` is supported for redemptions.
     */
    function isValidTokenOut(address token) public view override returns (bool) {
        return token == yieldBearingToken;
    }

    /**
     * @notice Returns metadata describing the asset represented by this SY.
     * @dev The adapter reports native BNB as the canonical asset with 18 decimals.
     * @return assetType The asset classification used by the SY interface.
     * @return assetAddress The underlying asset address.
     * @return assetDecimals The decimals used for the underlying asset.
     */
    function assetInfo() external pure returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        return (AssetType.TOKEN, NATIVE, 18);
    }
}
