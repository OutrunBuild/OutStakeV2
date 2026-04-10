// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

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
            // deposit() returns void — measure actual slisBNB output via balance diff.
            uint256 before = _selfBalance(yieldBearingToken);
            IListaStakeManager(STAKE_MANAGER).deposit{value: amountDeposited}();
            uint256 after_ = _selfBalance(yieldBearingToken);
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

    /**
     * @notice Returns the current BNB-per-slisBNB exchange rate.
     * @dev Quotes 1 slisBNB through the stake manager's conversion view.
     * @return res The current exchange rate scaled to 18 decimals.
     */
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

    /**
     * @notice Lists supported input tokens.
     * @dev Deposits accept native BNB or slisBNB.
     * @return res The supported deposit token list.
     */
    function getTokensIn() public view override returns (address[] memory res) {
        return ArrayLib.create(NATIVE, yieldBearingToken);
    }

    /**
     * @notice Lists supported output tokens.
     * @dev Redemptions only return slisBNB.
     * @return res The supported redemption token list.
     */
    function getTokensOut() public view override returns (address[] memory res) {
        return ArrayLib.create(yieldBearingToken);
    }

    /**
     * @notice Checks whether `token` can be deposited into this SY.
     * @dev Accepts native BNB and slisBNB.
     * @param token The token to validate.
     * @return Whether the token is supported as input.
     */
    function isValidTokenIn(address token) public view override returns (bool) {
        return token == NATIVE || token == yieldBearingToken;
    }

    /**
     * @notice Checks whether `token` can be redeemed from this SY.
     * @dev Redemption supports only slisBNB output.
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

    function _requireNonZeroArgs(address slisBnb, address stakeManager) private pure returns (address) {
        if (slisBnb == address(0) || stakeManager == address(0)) revert SYZeroAddress();
        return slisBnb;
    }
}
