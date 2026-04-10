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
    error AsBnbMintZeroShares();
    error InvalidAsBnbMinterAsBnb(address expected, address actual);
    error InvalidAsBnbMinterToken(address expected, address actual);
    error InvalidYieldProxy();
    error InvalidStakeManager();

    constructor(address _owner, address _asBNB, address _slisBNB, address _asBnbMinter)
        SYBase("SY Aster asBNB", "SY asBNB", _requireNonZeroConstructorArgs(_asBNB, _slisBNB, _asBnbMinter), _owner)
    {
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
            // Trust boundary: upstream mints asBNB to address(this) and returns the real shares actually received.
            amountSharesOut = IAsBnbMinter(AS_BNB_MINTER).mintAsBnb{value: amountDeposited}();
            if (amountSharesOut == 0) _revertOnZeroShares();
            return amountSharesOut;
        }

        if (tokenIn == SLIS_BNB) {
            _safeApproveInf(SLIS_BNB, AS_BNB_MINTER);
            // Trust boundary: upstream mints asBNB to address(this) and returns the real shares actually received.
            amountSharesOut = IAsBnbMinter(AS_BNB_MINTER).mintAsBnb(amountDeposited);
            if (amountSharesOut == 0) _revertOnZeroShares();
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

    /**
     * @notice Returns the current BNB-per-asBNB exchange rate for this Aster SY.
     * @dev Quotes one asBNB share through the asBNB->slisBNB minter path and the slisBNB->BNB stake-manager path.
     * @return res The current exchange rate scaled to 18 decimals.
     */
    function exchangeRate() public view override returns (uint256 res) {
        uint256 slisBnbPerShare = IAsBnbMinter(AS_BNB_MINTER).convertToTokens(1 ether);
        return IListaBNBStakeManager(STAKE_MANAGER).convertSnBnbToBnb(slisBnbPerShare);
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

    /**
     * @notice Lists supported input tokens.
     * @dev Deposits accept native BNB, slisBNB, or asBNB.
     * @return res The supported deposit token list.
     */
    function getTokensIn() public view override returns (address[] memory res) {
        return ArrayLib.create(NATIVE, SLIS_BNB, yieldBearingToken);
    }

    /**
     * @notice Lists supported output tokens.
     * @dev Redemptions only return asBNB.
     * @return res The supported redemption token list.
     */
    function getTokensOut() public view override returns (address[] memory res) {
        return ArrayLib.create(yieldBearingToken);
    }

    /**
     * @notice Checks whether `token` can be deposited into this SY.
     * @dev Accepts native BNB, slisBNB, and the wrapped yield-bearing token.
     * @param token The token to validate.
     * @return Whether the token is supported as input.
     */
    function isValidTokenIn(address token) public view override returns (bool) {
        return token == NATIVE || token == SLIS_BNB || token == yieldBearingToken;
    }

    /**
     * @notice Checks whether `token` can be redeemed from this SY.
     * @dev Redemption supports only asBNB output.
     * @param token The token to validate.
     * @return Whether the token is supported as output.
     */
    function isValidTokenOut(address token) public view override returns (bool) {
        return token == yieldBearingToken;
    }

    /**
     * @notice Returns canonical asset metadata for integrations.
     * @dev The base asset exposed by this SY is native BNB with 18 decimals.
     * @return assetType The asset type for the underlying asset.
     * @return assetAddress The canonical underlying asset address.
     * @return assetDecimals The canonical underlying asset decimals.
     */
    function assetInfo() external pure returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        return (AssetType.TOKEN, NATIVE, 18);
    }

    function _requireNonZeroConstructorArgs(address asBnb, address slisBnb, address asBnbMinter)
        private
        pure
        returns (address)
    {
        if (asBnb == address(0) || slisBnb == address(0) || asBnbMinter == address(0)) revert SYZeroAddress();
        return asBnb;
    }

    function _revertOnZeroShares() private view {
        if (IYieldProxy(YIELD_PROXY).activitiesOnGoing()) revert AsBnbMintQueued();
        revert AsBnbMintZeroShares();
    }
}
