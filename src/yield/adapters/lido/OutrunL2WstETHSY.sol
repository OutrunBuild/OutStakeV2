// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {SYBase} from "../../SYBase.sol";
import {ArrayLib} from "../../../libraries/ArrayLib.sol";
import {IExchangeRateOracle} from "../../../libraries/oracle/interfaces/IExchangeRateOracle.sol";

contract OutrunL2WstETHSY is SYBase {
    address public immutable oracle;
    address internal immutable underlyingAssetOnEthAddr;
    uint8 internal immutable underlyingAssetOnEthDecimals;

    constructor(
        address _owner,
        address _wstETH,
        address _oracle,
        address _underlyingAssetOnEthAddr,
        uint8 _underlyingAssetOnEthDecimals
    ) SYBase("SY Lido wstETH", "SY wstETH", _wstETH, _owner) {
        oracle = _oracle;
        underlyingAssetOnEthAddr = _underlyingAssetOnEthAddr;
        underlyingAssetOnEthDecimals = _underlyingAssetOnEthDecimals;
    }

    function _deposit(
        address,
        /*tokenIn*/
        uint256 amountDeposited
    )
        internal
        pure
        override
        returns (uint256 amountSharesOut)
    {
        amountSharesOut = amountDeposited;
    }

    function _redeem(
        address receiver,
        address,
        /*tokenOut*/
        uint256 amountSharesToRedeem
    )
        internal
        override
        returns (uint256 amountTokenOut)
    {
        _transferOut(yieldBearingToken, receiver, amountSharesToRedeem);
        amountTokenOut = amountSharesToRedeem;
    }

    /// @notice Returns the oracle-backed exchange rate for wrapped stETH.
    /// @dev Reads the current rate from the configured exchange-rate oracle.
    /// @return res The current wrapped stETH exchange rate.
    function exchangeRate() public view override returns (uint256 res) {
        return IExchangeRateOracle(oracle).getExchangeRate();
    }

    function _previewDeposit(
        address,
        /*tokenIn*/
        uint256 amountTokenToDeposit
    )
        internal
        pure
        override
        returns (uint256 amountSharesOut)
    {
        amountSharesOut = amountTokenToDeposit;
    }

    function _previewRedeem(
        address,
        /*tokenOut*/
        uint256 amountSharesToRedeem
    )
        internal
        pure
        override
        returns (uint256 amountTokenOut)
    {
        amountTokenOut = amountSharesToRedeem;
    }

    /// @notice Lists supported input tokens.
    /// @dev This SY only accepts the wrapped yield-bearing token itself.
    /// @return res The supported deposit token list.
    function getTokensIn() public view override returns (address[] memory res) {
        return ArrayLib.create(yieldBearingToken);
    }

    /// @notice Lists supported output tokens.
    /// @dev Redemption returns the wrapped yield-bearing token itself.
    /// @return res The supported redemption token list.
    function getTokensOut() public view override returns (address[] memory res) {
        return ArrayLib.create(yieldBearingToken);
    }

    /// @notice Checks whether `token` can be deposited into this SY.
    /// @dev Only the wrapped yield-bearing token is accepted as input.
    /// @param token The token to validate.
    /// @return Whether the token is supported as input.
    function isValidTokenIn(address token) public view override returns (bool) {
        return token == yieldBearingToken;
    }

    /// @notice Checks whether `token` can be redeemed from this SY.
    /// @dev Only the wrapped yield-bearing token is available as output.
    /// @param token The token to validate.
    /// @return Whether the token is supported as output.
    function isValidTokenOut(address token) public view override returns (bool) {
        return token == yieldBearingToken;
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
