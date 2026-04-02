// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {SYBase} from "../../SYBase.sol";
import {ArrayLib} from "../../../libraries/ArrayLib.sol";
import {IL2StETH} from "../../../integrations/lido/interfaces/IL2StETH.sol";
import {IExchangeRateOracle} from "../../../libraries/oracle/interfaces/IExchangeRateOracle.sol";

contract OutrunL2WrappableWstETHSY is SYBase {
    using SafeERC20 for IERC20;

    address public immutable STETH;
    IExchangeRateOracle public immutable EXCHANGE_RATE_ORACLE;
    address internal immutable underlyingAssetOnEthAddr;
    uint8 internal immutable underlyingAssetOnEthDecimals;

    constructor(
        address _owner,
        address _stETH,
        address _wstETH,
        address _tokenRateOracle,
        address _underlyingAssetOnEthAddr,
        uint8 _underlyingAssetOnEthDecimals
    ) SYBase("SY Lido wstETH", "SY wstETH", _wstETH, _owner) {
        STETH = _stETH;
        EXCHANGE_RATE_ORACLE = IExchangeRateOracle(_tokenRateOracle);
        underlyingAssetOnEthAddr = _underlyingAssetOnEthAddr;
        underlyingAssetOnEthDecimals = _underlyingAssetOnEthDecimals;
    }

    function _deposit(address tokenIn, uint256 amountDeposited) internal override returns (uint256 amountSharesOut) {
        if (tokenIn == STETH) {
            amountSharesOut = IL2StETH(STETH).unwrap(amountDeposited);
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
            _safeApproveInf(yieldBearingToken, STETH);
            amountTokenOut = IL2StETH(STETH).wrap(amountSharesToRedeem);
            IERC20(STETH).safeTransfer(receiver, amountTokenOut);
        } else {
            amountTokenOut = amountSharesToRedeem;
            IERC20(yieldBearingToken).safeTransfer(receiver, amountTokenOut);
        }
    }

    /// @notice Returns the latest L2 wrapper exchange rate.
    /// @dev Reads the normalized exchange rate from the configured oracle abstraction.
    /// @return res The latest wrapper exchange rate.
    function exchangeRate() public view override returns (uint256 res) {
        return EXCHANGE_RATE_ORACLE.getExchangeRate();
    }

    function _previewDeposit(address tokenIn, uint256 amountTokenToDeposit)
        internal
        view
        override
        returns (uint256 amountSharesOut)
    {
        if (tokenIn == STETH) {
            amountSharesOut = IL2StETH(STETH).getSharesByTokens(amountTokenToDeposit);
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
            amountTokenOut = IL2StETH(STETH).getTokensByShares(amountSharesToRedeem);
        } else {
            amountTokenOut = amountSharesToRedeem;
        }
    }

    /// @notice Lists supported input tokens.
    /// @dev Deposits may arrive as either stETH or wstETH on L2.
    /// @return res The supported deposit token list.
    function getTokensIn() public view override returns (address[] memory res) {
        return ArrayLib.create(STETH, yieldBearingToken);
    }

    /// @notice Lists supported output tokens.
    /// @dev Redemptions may be requested as either stETH or wstETH.
    /// @return res The supported redemption token list.
    function getTokensOut() public view override returns (address[] memory res) {
        return ArrayLib.create(STETH, yieldBearingToken);
    }

    /// @notice Checks whether `token` can be deposited into this SY.
    /// @dev Accepts either wrapped or unwrapped stETH variants.
    /// @param token The token to validate.
    /// @return Whether the token is supported as input.
    function isValidTokenIn(address token) public view override returns (bool) {
        return token == STETH || token == yieldBearingToken;
    }

    /// @notice Checks whether `token` can be redeemed from this SY.
    /// @dev Allows redemption into either wrapped or unwrapped stETH variants.
    /// @param token The token to validate.
    /// @return Whether the token is supported as output.
    function isValidTokenOut(address token) public view override returns (bool) {
        return token == STETH || token == yieldBearingToken;
    }

    /// @notice Returns the canonical underlying asset metadata on Ethereum.
    /// @dev Exposes the base asset reference used by integrations.
    /// @return assetType The asset type for the underlying asset.
    /// @return assetAddress The canonical underlying asset address.
    /// @return assetDecimals The canonical underlying asset decimals.
    function assetInfo() external view returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        return (AssetType.TOKEN, underlyingAssetOnEthAddr, underlyingAssetOnEthDecimals);
    }
}
