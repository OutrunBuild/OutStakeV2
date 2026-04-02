// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {IMockAUSDC} from "../support/MockAUSDC.sol";
import {ArrayLib} from "../../src/libraries/ArrayLib.sol";
import {SYBase} from "../../src/yield/SYBase.sol";

/**
 * @dev Just For Memeverse Genesis Test
 */
contract MockOutrunAUSDCSY is SYBase {
    uint256 internal constant EXCHANGE_RATE_ONE = 1e18;

    address public immutable MOCK_USDC;
    address public immutable ORACLE;

    constructor(address _owner, address _mockUSDC, address _aUSDC, address _oracle)
        SYBase("SY Aave aUSDC", "SY aUSDC", _aUSDC, _owner)
    {
        MOCK_USDC = _mockUSDC;
        ORACLE = _oracle;
    }

    function _deposit(address tokenIn, uint256 amountDeposited) internal override returns (uint256 amountSharesOut) {
        if (tokenIn == MOCK_USDC) {
            _safeApproveInf(MOCK_USDC, yieldBearingToken);
            amountSharesOut = IMockAUSDC(yieldBearingToken).wrap(amountDeposited);
        } else {
            amountSharesOut = amountDeposited;
        }
    }

    function _redeem(address receiver, address tokenOut, uint256 amountSharesToRedeem)
        internal
        override
        returns (uint256 amountTokenOut)
    {
        if (tokenOut == MOCK_USDC) {
            amountTokenOut = IMockAUSDC(yieldBearingToken).unwrap(amountSharesToRedeem);
            _transferOut(MOCK_USDC, receiver, amountTokenOut);
        } else {
            amountTokenOut = amountSharesToRedeem;
            _transferOut(yieldBearingToken, receiver, amountSharesToRedeem);
        }
    }

    function exchangeRate() public view override returns (uint256 res) {
        ORACLE;
        return EXCHANGE_RATE_ONE;
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

    function getTokensIn() public view override returns (address[] memory res) {
        return ArrayLib.create(MOCK_USDC, yieldBearingToken);
    }

    function getTokensOut() public view override returns (address[] memory res) {
        return ArrayLib.create(MOCK_USDC, yieldBearingToken);
    }

    function isValidTokenIn(address token) public view override returns (bool) {
        return token == MOCK_USDC || token == yieldBearingToken;
    }

    function isValidTokenOut(address token) public view override returns (bool) {
        return token == MOCK_USDC || token == yieldBearingToken;
    }

    function assetInfo() external view returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        return (AssetType.TOKEN, MOCK_USDC, 18);
    }
}
