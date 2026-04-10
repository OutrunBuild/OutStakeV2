// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IListaStakeManager} from "../../../integrations/lista/interfaces/IListaStakeManager.sol";
import {ArrayLib} from "../../../libraries/ArrayLib.sol";
import {SYBase} from "../../SYBase.sol";

contract OutrunSlisBNBSY is SYBase {
    address public immutable STAKE_MANAGER;

    error InvalidStakeManager();
    error StakeManagerDepositZero();

    constructor(address _owner, address _slisBNB, address _stakeManager)
        SYBase("SY Lista slisBNB", "SY slisBNB", _requireNonZeroArgs(_slisBNB, _stakeManager), _owner)
    {
        if (IListaStakeManager(_stakeManager).convertSnBnbToBnb(1 ether) < 1 ether) {
            revert InvalidStakeManager();
        }
        STAKE_MANAGER = _stakeManager;
    }

    function _deposit(address tokenIn, uint256 amountDeposited) internal override returns (uint256 amountSharesOut) {
        if (tokenIn == NATIVE) {
            uint256 before = IERC20(yieldBearingToken).balanceOf(address(this));
            IListaStakeManager(STAKE_MANAGER).deposit{value: amountDeposited}();
            uint256 after_ = IERC20(yieldBearingToken).balanceOf(address(this));
            amountSharesOut = after_ - before;
            if (amountSharesOut == 0) revert StakeManagerDepositZero();
            return amountSharesOut;
        }

        // slisBNB / yieldBearingToken: 1:1 pass-through
        return amountDeposited;
    }

    function _redeem(address receiver, address tokenOut, uint256 amountSharesToRedeem)
        internal
        override
        returns (uint256 amountTokenOut)
    {
        amountTokenOut = amountSharesToRedeem;
        _transferOut(tokenOut, receiver, amountTokenOut);
    }

    function exchangeRate() public view override returns (uint256 res) {
        return IListaStakeManager(STAKE_MANAGER).convertSnBnbToBnb(1 ether);
    }

    function _previewDeposit(address tokenIn, uint256 amountTokenToDeposit)
        internal
        view
        override
        returns (uint256 amountSharesOut)
    {
        if (tokenIn == NATIVE) {
            return IListaStakeManager(STAKE_MANAGER).convertBnbToSnBnb(amountTokenToDeposit);
        }

        return amountTokenToDeposit;
    }

    function _previewRedeem(address, uint256 amountSharesToRedeem)
        internal
        pure
        override
        returns (uint256 amountTokenOut)
    {
        return amountSharesToRedeem;
    }

    function getTokensIn() public view override returns (address[] memory res) {
        return ArrayLib.create(NATIVE, yieldBearingToken);
    }

    function getTokensOut() public view override returns (address[] memory res) {
        return ArrayLib.create(yieldBearingToken);
    }

    function isValidTokenIn(address token) public view override returns (bool) {
        return token == NATIVE || token == yieldBearingToken;
    }

    function isValidTokenOut(address token) public view override returns (bool) {
        return token == yieldBearingToken;
    }

    function assetInfo() external pure returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        return (AssetType.TOKEN, NATIVE, 18);
    }

    function _requireNonZeroArgs(address slisBnb, address stakeManager) private pure returns (address) {
        if (slisBnb == address(0) || stakeManager == address(0)) revert SYZeroAddress();
        return slisBnb;
    }
}
