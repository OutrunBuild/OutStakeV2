// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {SYBaseUpgradeable} from "../../SYBaseUpgradeable.sol";
import {ArrayLib} from "../../../libraries/ArrayLib.sol";
import {IWeETH} from "../../../integrations/etherfi/interfaces/IWeETH.sol";
import {ILiquidityPool} from "../../../integrations/etherfi/interfaces/ILiquidityPool.sol";
import {IDepositAdapter} from "../../../integrations/etherfi/interfaces/IDepositAdapter.sol";

contract OutrunWeETHSYUpgradeable is SYBaseUpgradeable {
    /// @custom:storage-location erc7201:outrun.storage.OutrunWeETHSY
    // forge-lint: disable-next-line(pascal-case-struct)
    struct OutrunWeETHSYStorage {
        address EETH;
        address DEPOSIT_ADAPTER;
        address LIQUIDITY_POOL;
    }

    // keccak256(abi.encode(uint256(keccak256("outrun.storage.OutrunWeETHSY")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant OUTRUN_WE_ETH_SY_STORAGE_LOCATION =
        0x7c889822051b104e8bf752526ae310e0de27a4e1749297b1b10b3e2ca8c5af00;

    function initialize(address owner_, address eETH_, address weETH_, address depositAdapter_, address liquidityPool_)
        external
        initializer
    {
        if (eETH_ == address(0) || depositAdapter_ == address(0) || liquidityPool_ == address(0)) {
            revert SYZeroAddress();
        }
        __SYBase_init("SY Etherfi weETH", "SY weETH", weETH_, owner_);
        OutrunWeETHSYStorage storage $ = _getStorage();
        $.EETH = eETH_;
        $.DEPOSIT_ADAPTER = depositAdapter_;
        $.LIQUIDITY_POOL = liquidityPool_;
    }

    function _getStorage() private pure returns (OutrunWeETHSYStorage storage $) {
        // slither-disable-next-line assembly
        assembly {
            $.slot := OUTRUN_WE_ETH_SY_STORAGE_LOCATION
        }
    }

    function EETH() public view returns (address) {
        return _getStorage().EETH;
    }

    function DEPOSIT_ADAPTER() public view returns (address) {
        return _getStorage().DEPOSIT_ADAPTER;
    }

    function LIQUIDITY_POOL() public view returns (address) {
        return _getStorage().LIQUIDITY_POOL;
    }

    function _deposit(address tokenIn, uint256 amountDeposited) internal override returns (uint256 amountSharesOut) {
        if (tokenIn == NATIVE) {
            amountSharesOut = IDepositAdapter(DEPOSIT_ADAPTER()).depositETHForWeETH{value: amountDeposited}(address(0));
        } else if (tokenIn == EETH()) {
            _safeApproveInf(EETH(), yieldBearingToken());
            amountSharesOut = IWeETH(yieldBearingToken()).wrap(amountDeposited);
        } else {
            amountSharesOut = amountDeposited;
        }
    }

    function _redeem(address receiver, address tokenOut, uint256 amountSharesToRedeem)
        internal
        override
        returns (uint256 amountTokenOut)
    {
        address _EETH = EETH();
        address _yieldBearingToken = yieldBearingToken();
        if (tokenOut == _EETH) {
            amountTokenOut = IWeETH(_yieldBearingToken).unwrap(amountSharesToRedeem);
            _transferOut(_EETH, receiver, amountTokenOut);
        } else {
            amountTokenOut = amountSharesToRedeem;
            _transferOut(_yieldBearingToken, receiver, amountSharesToRedeem);
        }
    }

    function exchangeRate() public view override returns (uint256 res) {
        return ILiquidityPool(LIQUIDITY_POOL()).amountForShare(1 ether);
    }

    function _previewDeposit(address tokenIn, uint256 amountTokenToDeposit)
        internal
        view
        override
        returns (uint256 amountSharesOut)
    {
        address _pool = LIQUIDITY_POOL();
        if (tokenIn == NATIVE) {
            uint256 eETHAmount =
                ILiquidityPool(_pool).amountForShare(ILiquidityPool(_pool).sharesForAmount(amountTokenToDeposit));
            amountSharesOut = ILiquidityPool(_pool).sharesForAmount(eETHAmount);
        } else if (tokenIn == EETH()) {
            amountSharesOut = ILiquidityPool(_pool).sharesForAmount(amountTokenToDeposit);
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
        if (tokenOut == EETH()) {
            amountTokenOut = ILiquidityPool(LIQUIDITY_POOL()).amountForShare(amountSharesToRedeem);
        } else {
            amountTokenOut = amountSharesToRedeem;
        }
    }

    function getTokensIn() public view override returns (address[] memory res) {
        return ArrayLib.create(NATIVE, EETH(), yieldBearingToken());
    }

    function getTokensOut() public view override returns (address[] memory res) {
        return ArrayLib.create(EETH(), yieldBearingToken());
    }

    function isValidTokenIn(address token) public view override returns (bool) {
        return token == NATIVE || token == EETH() || token == yieldBearingToken();
    }

    function isValidTokenOut(address token) public view override returns (bool) {
        return token == EETH() || token == yieldBearingToken();
    }

    function assetInfo() external pure returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        return (AssetType.TOKEN, NATIVE, 18);
    }
}
