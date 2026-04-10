// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {IAsBnbMinter} from "../../../integrations/aster/interfaces/IAsBnbMinter.sol";
import {IListaBNBStakeManager} from "../../../integrations/aster/interfaces/IListaBNBStakeManager.sol";
import {IYieldProxy} from "../../../integrations/aster/interfaces/IYieldProxy.sol";
import {ArrayLib} from "../../../libraries/ArrayLib.sol";
import {SYBase} from "../../SYBase.sol";

contract OutrunAsBNBSY is SYBase {
    address public immutable AS_BNB_MINTER;
    address public immutable SLIS_BNB;
    address public immutable YIELD_PROXY;
    address public immutable STAKE_MANAGER;

    error AsBnbMintQueued();
    error InvalidAsBnbMinterAsBnb(address expected, address actual);
    error InvalidAsBnbMinterToken(address expected, address actual);
    error InvalidYieldProxy();
    error InvalidStakeManager();

    constructor(address _owner, address _asBNB, address _slisBNB, address _asBnbMinter)
        SYBase("SY Aster asBNB", "SY asBNB", _requireNonZeroYieldBearingToken(_asBNB), _owner)
    {
        if (_slisBNB == address(0) || _asBnbMinter == address(0)) revert SYZeroAddress();

        address actualAsBnb = IAsBnbMinter(_asBnbMinter).asBnb();
        if (actualAsBnb != _asBNB) revert InvalidAsBnbMinterAsBnb(_asBNB, actualAsBnb);

        address actualToken = IAsBnbMinter(_asBnbMinter).token();
        if (actualToken != _slisBNB) revert InvalidAsBnbMinterToken(_slisBNB, actualToken);

        address yieldProxy = IAsBnbMinter(_asBnbMinter).yieldProxy();
        if (yieldProxy == address(0)) revert InvalidYieldProxy();

        address stakeManager = IYieldProxy(yieldProxy).stakeManager();
        if (stakeManager == address(0)) revert InvalidStakeManager();

        AS_BNB_MINTER = _asBnbMinter;
        SLIS_BNB = _slisBNB;
        YIELD_PROXY = yieldProxy;
        STAKE_MANAGER = stakeManager;
    }

    function _deposit(address tokenIn, uint256 amountDeposited) internal override returns (uint256 amountSharesOut) {
        if (tokenIn == NATIVE) {
            // Aster may queue mint requests instead of minting immediately; SY cannot represent that async state.
            amountSharesOut = IAsBnbMinter(AS_BNB_MINTER).mintAsBnb{value: amountDeposited}();
            if (amountSharesOut == 0) revert AsBnbMintQueued();
            return amountSharesOut;
        }

        if (tokenIn == SLIS_BNB) {
            _safeApproveInf(SLIS_BNB, AS_BNB_MINTER);
            amountSharesOut = IAsBnbMinter(AS_BNB_MINTER).mintAsBnb(amountDeposited);
            if (amountSharesOut == 0) revert AsBnbMintQueued();
            return amountSharesOut;
        }

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
        return IAsBnbMinter(AS_BNB_MINTER).convertToTokens(1 ether);
    }

    function _previewDeposit(address tokenIn, uint256 amountTokenToDeposit)
        internal
        view
        override
        returns (uint256 amountSharesOut)
    {
        if (tokenIn == NATIVE) {
            uint256 slisBnbAmount = IListaBNBStakeManager(STAKE_MANAGER).convertBnbToSnBnb(amountTokenToDeposit);
            return IAsBnbMinter(AS_BNB_MINTER).convertToAsBnb(slisBnbAmount);
        }

        if (tokenIn == SLIS_BNB) {
            return IAsBnbMinter(AS_BNB_MINTER).convertToAsBnb(amountTokenToDeposit);
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
        return ArrayLib.create(NATIVE, SLIS_BNB, yieldBearingToken);
    }

    function getTokensOut() public view override returns (address[] memory res) {
        return ArrayLib.create(yieldBearingToken);
    }

    function isValidTokenIn(address token) public view override returns (bool) {
        return token == NATIVE || token == SLIS_BNB || token == yieldBearingToken;
    }

    function isValidTokenOut(address token) public view override returns (bool) {
        return token == yieldBearingToken;
    }

    function assetInfo() external pure returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        return (AssetType.TOKEN, NATIVE, 18);
    }

    function _requireNonZeroYieldBearingToken(address token) private pure returns (address) {
        if (token == address(0)) revert SYZeroAddress();
        return token;
    }
}
