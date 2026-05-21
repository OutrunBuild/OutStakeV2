// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {SYBaseUpgradeable} from "../../SYBaseUpgradeable.sol";
import {ArrayLib} from "../../../libraries/ArrayLib.sol";
import {IWeETH} from "../../../integrations/etherfi/interfaces/IWeETH.sol";
import {ILiquidityPool} from "../../../integrations/etherfi/interfaces/ILiquidityPool.sol";
import {IDepositAdapter} from "../../../integrations/etherfi/interfaces/IDepositAdapter.sol";

// SY adapter for EtherFi weETH.
// The yield-bearing token is weETH (wrapped eETH).
// Deposit paths:
//   (a) native ETH → DepositAdapter → weETH,
//   (b) eETH → wrap to weETH,
//   (c) existing weETH directly.
// Exchange rate comes from LiquidityPool.amountForShare.
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

    /// @param owner_ initial owner of the SY contract
    /// @param eETH_ EtherFi eETH token address
    /// @param weETH_ EtherFi weETH token address (yield-bearing token for this SY)
    /// @param depositAdapter_ EtherFi DepositAdapter for ETH to weETH conversion
    /// @param liquidityPool_ EtherFi LiquidityPool address
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

    /// @notice The EtherFi eETH token address
    /// @return address of the eETH ERC20 token
    function EETH() public view returns (address) {
        return _getStorage().EETH;
    }

    /// @notice EtherFi DepositAdapter for ETH to weETH conversion
    /// @return address of the DepositAdapter contract
    function DEPOSIT_ADAPTER() public view returns (address) {
        return _getStorage().DEPOSIT_ADAPTER;
    }

    /// @notice EtherFi LiquidityPool used for exchange rate queries
    /// @return address of the LiquidityPool contract
    function LIQUIDITY_POOL() public view returns (address) {
        return _getStorage().LIQUIDITY_POOL;
    }

    /// @notice Three deposit paths: NATIVE -> Adapter, EETH -> wrap, weETH -> 1:1.
    /// Native ETH is routed through EtherFi's DepositAdapter. eETH is wrapped into
    /// weETH via the weETH contract. Existing weETH is deposited 1:1.
    /// @param tokenIn the asset being deposited (NATIVE, eETH, or weETH)
    /// @param amountDeposited amount of tokenIn to deposit
    /// @return amountSharesOut amount of weETH shares credited
    function _deposit(address tokenIn, uint256 amountDeposited) internal override returns (uint256 amountSharesOut) {
        if (tokenIn == NATIVE) {
            // Route native ETH through EtherFi's DepositAdapter which handles staking and mints weETH.
            amountSharesOut = IDepositAdapter(DEPOSIT_ADAPTER()).depositETHForWeETH{value: amountDeposited}(address(0));
        } else if (tokenIn == EETH()) {
            // Wrap existing eETH into weETH via the weETH contract.
            _safeApproveInf(EETH(), yieldBearingToken());
            amountSharesOut = IWeETH(yieldBearingToken()).wrap(amountDeposited);
        } else {
            // Already in weETH form, 1:1 deposit.
            amountSharesOut = amountDeposited;
        }
    }

    /// @notice Redeem weETH shares: unwrap to eETH or transfer weETH directly.
    /// @param receiver address to receive the redeemed tokens
    /// @param tokenOut the asset to redeem (eETH or weETH)
    /// @param amountSharesToRedeem amount of weETH shares to redeem
    /// @return amountTokenOut amount of tokenOut received
    function _redeem(address receiver, address tokenOut, uint256 amountSharesToRedeem)
        internal
        override
        returns (uint256 amountTokenOut)
    {
        // Redeem to eETH (unwrap weETH) or transfer weETH directly.
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

    /// @notice EtherFi LiquidityPool.amountForShare — the ETH value of one weETH share.
    /// @return res exchange rate in 1e18 precision
    function exchangeRate() public view override returns (uint256 res) {
        return ILiquidityPool(LIQUIDITY_POOL()).amountForShare(1 ether);
    }

    /// @notice ETH -> eETH -> weETH two-step preview.
    /// For native ETH, first computes how much eETH the ETH buys,
    /// then converts that eETH to weETH shares via the LiquidityPool.
    /// @param tokenIn the token being deposited (NATIVE, eETH, or weETH)
    /// @param amountTokenToDeposit amount of tokenIn to deposit
    /// @return amountSharesOut expected weETH shares
    function _previewDeposit(address tokenIn, uint256 amountTokenToDeposit)
        internal
        view
        override
        returns (uint256 amountSharesOut)
    {
        address _pool = LIQUIDITY_POOL();
        if (tokenIn == NATIVE) {
            // ETH → eETH → weETH conversion.
            // First compute how much eETH the ETH buys, then how much weETH that eETH represents.
            uint256 eETHAmount =
                ILiquidityPool(_pool).amountForShare(ILiquidityPool(_pool).sharesForAmount(amountTokenToDeposit));
            amountSharesOut = ILiquidityPool(_pool).sharesForAmount(eETHAmount);
        } else if (tokenIn == EETH()) {
            amountSharesOut = ILiquidityPool(_pool).sharesForAmount(amountTokenToDeposit);
        } else {
            amountSharesOut = amountTokenToDeposit;
        }
    }

    /// @notice Preview the amount received for a given share redemption.
    /// @param tokenOut the token to redeem to (eETH or weETH)
    /// @param amountSharesToRedeem amount of weETH shares to redeem
    /// @return amountTokenOut expected amount of tokenOut
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

    /// @notice Returns the list of tokens accepted for deposit.
    /// @return res array containing NATIVE, eETH, and weETH
    function getTokensIn() public view override returns (address[] memory res) {
        return ArrayLib.create(NATIVE, EETH(), yieldBearingToken());
    }

    /// @notice Returns the list of tokens accepted for redemption.
    /// @return res array containing eETH and weETH
    function getTokensOut() public view override returns (address[] memory res) {
        return ArrayLib.create(EETH(), yieldBearingToken());
    }

    /// @notice Checks whether a given token is a valid input for deposit.
    /// @param token address of the token to check
    /// @return true if token is NATIVE, eETH, or weETH
    function isValidTokenIn(address token) public view override returns (bool) {
        return token == NATIVE || token == EETH() || token == yieldBearingToken();
    }

    /// @notice Checks whether a given token is a valid output for redemption.
    /// @param token address of the token to check
    /// @return true if token is eETH or weETH
    function isValidTokenOut(address token) public view override returns (bool) {
        return token == EETH() || token == yieldBearingToken();
    }

    function assetInfo() external pure returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        return (AssetType.TOKEN, NATIVE, 18);
    }
}
