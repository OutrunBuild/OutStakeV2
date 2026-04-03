// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {IAToken} from "../../../integrations/aave/interfaces/IAToken.sol";
import {ArrayLib} from "../../../libraries/ArrayLib.sol";
import {SYBase, IERC20Metadata} from "../../SYBase.sol";
import {IAaveV3Pool} from "../../../integrations/aave/interfaces/IAaveV3Pool.sol";
import {AaveAdapterLib} from "../../../libraries/AaveAdapterLib.sol";

contract OutrunAaveV3SY is SYBase {
    address public immutable underlying;
    address public immutable aavePool;

    constructor(string memory _name, string memory _symbol, address _aToken, address _aavePool, address _owner)
        SYBase(_name, _symbol, _aToken, _owner)
    {
        underlying = IAToken(_aToken).UNDERLYING_ASSET_ADDRESS();
        aavePool = _aavePool;
    }

    function _deposit(address tokenIn, uint256 amountDeposited) internal override returns (uint256 amountSharesOut) {
        if (tokenIn == underlying) {
            _safeApproveInf(underlying, aavePool);
            IAaveV3Pool(aavePool).supply(underlying, amountDeposited, address(this), 0);
        }
        amountSharesOut = AaveAdapterLib.calcSharesFromAssetUp(amountDeposited, _getNormalizedIncome());
    }

    function _redeem(address receiver, address tokenOut, uint256 amountSharesToRedeem)
        internal
        override
        returns (uint256 amountTokenOut)
    {
        amountTokenOut = AaveAdapterLib.calcSharesToAssetDown(amountSharesToRedeem, _getNormalizedIncome());
        if (tokenOut == underlying) {
            IAaveV3Pool(aavePool).withdraw(underlying, amountTokenOut, receiver);
        } else {
            _transferOut(yieldBearingToken, receiver, amountTokenOut);
        }
    }

    /**
     * @notice Returns the current asset-per-share rate for this Aave SY.
     * @dev The rate is derived from Aave's normalized income and scaled back to 1e18 precision.
     * @return The current exchange rate between shares and the underlying asset.
     */
    function exchangeRate() public view virtual override returns (uint256) {
        return _getNormalizedIncome() / 1e9;
    }

    function _previewDeposit(
        address,
        /*tokenIn*/
        uint256 amountTokenToDeposit
    )
        internal
        view
        override
        returns (uint256 amountSharesOut)
    {
        amountSharesOut = AaveAdapterLib.calcSharesFromAssetUp(amountTokenToDeposit, _getNormalizedIncome());
    }

    function _previewRedeem(
        address,
        /*tokenOut*/
        uint256 amountSharesToRedeem
    )
        internal
        view
        override
        returns (uint256 amountTokenOut)
    {
        amountTokenOut = AaveAdapterLib.calcSharesToAssetDown(amountSharesToRedeem, _getNormalizedIncome());
    }

    function _getNormalizedIncome() internal view returns (uint256) {
        return IAaveV3Pool(aavePool).getReserveNormalizedIncome(underlying);
    }

    /**
     * @notice Returns the tokens accepted for deposits into this SY.
     * @dev Deposits can be made with either the underlying asset or the yield-bearing aToken.
     * @return res The supported deposit token list.
     */
    function getTokensIn() public view override returns (address[] memory res) {
        return ArrayLib.create(underlying, yieldBearingToken);
    }

    /**
     * @notice Returns the tokens redeemable from this SY.
     * @dev Redemptions can settle into either the underlying asset or the yield-bearing aToken.
     * @return res The supported redemption token list.
     */
    function getTokensOut() public view override returns (address[] memory res) {
        return ArrayLib.create(underlying, yieldBearingToken);
    }

    /**
     * @notice Returns whether `token` is accepted on deposit.
     * @dev Only the underlying asset and the configured aToken are valid deposit inputs.
     * @param token The token to validate.
     * @return True when `token` is supported for deposits.
     */
    function isValidTokenIn(address token) public view override returns (bool) {
        return token == underlying || token == yieldBearingToken;
    }

    /**
     * @notice Returns whether `token` is accepted on redemption.
     * @dev Only the underlying asset and the configured aToken are valid redemption outputs.
     * @param token The token to validate.
     * @return True when `token` is supported for redemptions.
     */
    function isValidTokenOut(address token) public view override returns (bool) {
        return token == underlying || token == yieldBearingToken;
    }

    /**
     * @notice Returns metadata describing the asset represented by this SY.
     * @dev The adapter reports the Aave reserve underlying as the canonical asset.
     * @return assetType The asset classification used by the SY interface.
     * @return assetAddress The underlying asset address.
     * @return assetDecimals The decimals reported by the underlying token.
     */
    function assetInfo() external view returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        return (AssetType.TOKEN, underlying, IERC20Metadata(underlying).decimals());
    }
}
