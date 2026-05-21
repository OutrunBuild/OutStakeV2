// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {IAToken} from "../../../integrations/aave/interfaces/IAToken.sol";
import {IAaveV3Pool} from "../../../integrations/aave/interfaces/IAaveV3Pool.sol";
import {ArrayLib} from "../../../libraries/ArrayLib.sol";
import {AaveAdapterLib} from "../../../libraries/AaveAdapterLib.sol";
import {SYBaseUpgradeable} from "../../SYBaseUpgradeable.sol";

// SY adapter for Aave V3.
// The yield-bearing token is the aToken (e.g., aUSDC).
// Deposit paths:
//   (a) deposit the underlying asset into Aave to receive aToken shares,
//   (b) deposit existing aToken directly as SY.
// Exchange rate uses Aave's liquidity index (ray-scaled) divided by 1e9
// to get the 1e18-scaled rate.
contract OutrunAaveV3SYUpgradeable is SYBaseUpgradeable {
    /// @custom:storage-location erc7201:outrun.storage.OutrunAaveV3SY
    // forge-lint: disable-next-line(pascal-case-struct)
    struct OutrunAaveV3SYStorage {
        address underlying;
        address aavePool;
    }

    // keccak256(abi.encode(uint256(keccak256("outrun.storage.OutrunAaveV3SY")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant OUTRUN_AAVE_V3_SY_STORAGE_LOCATION =
        0x72217a3ea688bfbd31b48bb32b412c4301717e3e5d9754c566b8b7af0c910a00;
    error AaveZeroShares();

    /// @param name_ SY token name
    /// @param symbol_ SY token symbol
    /// @param aToken_ Aave aToken address (yield-bearing token for this SY)
    /// @param aavePool_ Aave V3 pool address
    /// @param owner_ initial owner of the SY contract
    function initialize(
        string calldata name_,
        string calldata symbol_,
        address aToken_,
        address aavePool_,
        address owner_
    ) external initializer {
        if (aavePool_ == address(0)) revert SYZeroAddress();
        __SYBase_init(name_, symbol_, aToken_, owner_);
        OutrunAaveV3SYStorage storage $ = _getStorage();
        $.underlying = IAToken(aToken_).UNDERLYING_ASSET_ADDRESS();
        $.aavePool = aavePool_;
    }

    function _getStorage() private pure returns (OutrunAaveV3SYStorage storage $) {
        // slither-disable-next-line assembly
        assembly {
            $.slot := OUTRUN_AAVE_V3_SY_STORAGE_LOCATION
        }
    }

    /// @notice The underlying asset that this SY represents (e.g., USDC for aUSDC)
    /// @return address of the underlying ERC20 token
    function underlying() public view returns (address) {
        return _getStorage().underlying;
    }

    /// @notice The Aave V3 pool used for supply/withdraw operations
    /// @return address of the Aave V3 pool contract
    function aavePool() public view returns (address) {
        return _getStorage().aavePool;
    }

    /// @notice Deposit: supply underlying to Aave or wrap aToken.
    /// When depositing underlying, the function supplies to Aave and returns
    /// the scaled balance difference. When depositing an aToken directly, it
    /// converts the token amount to scaled shares using the current liquidity index.
    /// @param tokenIn the asset being deposited (underlying or aToken)
    /// @param amountDeposited amount of tokenIn to deposit
    /// @return amountSharesOut scaled shares credited
    // slither-disable-next-line reentrancy-no-eth
    function _deposit(address tokenIn, uint256 amountDeposited) internal override returns (uint256 amountSharesOut) {
        address _underlying = underlying();
        address _pool = aavePool();
        if (tokenIn == _underlying) {
            // Supply the underlying asset to Aave pool.
            // Track scaled balance before/after because aToken balance changes with the liquidity index.
            IAToken aToken = IAToken(yieldBearingToken());
            uint256 scaledBefore = aToken.scaledBalanceOf(address(this));
            _safeApproveInf(_underlying, _pool);
            IAaveV3Pool(_pool).supply(_underlying, amountDeposited, address(this), 0);
            amountSharesOut = aToken.scaledBalanceOf(address(this)) - scaledBefore;
        } else {
            // Deposit aToken directly — convert to scaled shares using current liquidity index.
            amountSharesOut = AaveAdapterLib.calcSharesFromAssetUp(amountDeposited, _getNormalizedIncome());
        }
        if (amountSharesOut == 0) revert AaveZeroShares();
    }

    /// @notice Redeem: withdraw from Aave or transfer aToken.
    /// Converts scaled shares to asset amount using the current liquidity index,
    /// then either withdraws from the Aave pool (if redeeming to underlying)
    /// or transfers the aToken directly.
    /// @param receiver address to receive the redeemed tokens
    /// @param tokenOut the asset being redeemed (underlying or aToken)
    /// @param amountSharesToRedeem scaled shares to redeem
    /// @return amountTokenOut amount of tokenOut received
    function _redeem(address receiver, address tokenOut, uint256 amountSharesToRedeem)
        internal
        override
        returns (uint256 amountTokenOut)
    {
        // Convert scaled shares back to asset amount using current liquidity index,
        // then either withdraw from Aave (if redeeming to underlying)
        // or transfer aToken directly (if redeeming to aToken).
        amountTokenOut = AaveAdapterLib.calcSharesToAssetDown(amountSharesToRedeem, _getNormalizedIncome());
        address _underlying = underlying();
        if (tokenOut == _underlying) {
            address _pool = aavePool();
            amountTokenOut = IAaveV3Pool(_pool).withdraw(_underlying, amountTokenOut, receiver);
        } else {
            _transferOut(yieldBearingToken(), receiver, amountTokenOut);
        }
    }

    /// @notice Aave liquidity index / 1e9 = canonical asset per SY.
    /// Aave's liquidity index is ray-scaled (1e27).
    /// Divide by 1e9 to get the standard 1e18-scaled exchange rate.
    /// @return exchange rate in 1e18 precision
    function exchangeRate() public view override returns (uint256) {
        // Aave's liquidity index is ray-scaled (1e27).
        // Divide by 1e9 to get the standard 1e18-scaled exchange rate.
        return _getNormalizedIncome() / 1e9;
    }

    /// @notice Preview the scaled shares received for a given deposit.
    /// @param amountTokenToDeposit amount of token to deposit
    /// @return amountSharesOut expected scaled shares
    function _previewDeposit(address, uint256 amountTokenToDeposit) internal view override returns (uint256) {
        return AaveAdapterLib.calcSharesFromAssetUp(amountTokenToDeposit, _getNormalizedIncome());
    }

    /// @notice Preview the asset amount received for a given share redemption.
    /// @param amountSharesToRedeem scaled shares to redeem
    /// @return amountTokenOut expected asset amount
    function _previewRedeem(address, uint256 amountSharesToRedeem) internal view override returns (uint256) {
        return AaveAdapterLib.calcSharesToAssetDown(amountSharesToRedeem, _getNormalizedIncome());
    }

    /// @notice Queries the Aave pool for the current liquidity index of the underlying reserve.
    /// @return the normalized income (liquidity index) in ray (1e27) precision
    function _getNormalizedIncome() internal view returns (uint256) {
        return IAaveV3Pool(aavePool()).getReserveNormalizedIncome(underlying());
    }

    /// @notice Returns the list of tokens accepted for deposit.
    /// @return res array containing the underlying asset and the yield-bearing aToken
    function getTokensIn() public view override returns (address[] memory res) {
        return ArrayLib.create(underlying(), yieldBearingToken());
    }

    /// @notice Returns the list of tokens accepted for redemption.
    /// @return res array containing the underlying asset and the yield-bearing aToken
    function getTokensOut() public view override returns (address[] memory res) {
        return ArrayLib.create(underlying(), yieldBearingToken());
    }

    /// @notice Checks whether a given token is a valid input for deposit.
    /// @param token address of the token to check
    /// @return true if token is the underlying asset or the yield-bearing aToken
    function isValidTokenIn(address token) public view override returns (bool) {
        return token == underlying() || token == yieldBearingToken();
    }

    /// @notice Checks whether a given token is a valid output for redemption.
    /// @param token address of the token to check
    /// @return true if token is the underlying asset or the yield-bearing aToken
    function isValidTokenOut(address token) public view override returns (bool) {
        return token == underlying() || token == yieldBearingToken();
    }

    /// @notice Returns asset metadata: type, address, and decimals of the underlying token.
    /// @return assetType always TOKEN for this adapter
    /// @return assetAddress address of the underlying asset
    /// @return assetDecimals decimals of the underlying asset
    function assetInfo() external view returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        address _underlying = underlying();
        return (AssetType.TOKEN, _underlying, IERC20Metadata(_underlying).decimals());
    }
}
