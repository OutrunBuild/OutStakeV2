// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IStandardizedYield is IERC20Metadata {
    /**
     *
     */
    error SYInvalidTokenIn(address token);

    error SYInvalidTokenOut(address token);

    error SYZeroAddress();

    error SYZeroDeposit();

    error SYZeroRedeem();

    error SYInsufficientSharesOut(uint256 actualSharesOut, uint256 requiredSharesOut);

    error SYInsufficientTokenOut(uint256 actualTokenOut, uint256 requiredTokenOut);

    /// @dev Emitted when any base tokens is deposited to mint shares
    event Deposit(
        address indexed caller,
        address indexed receiver,
        address indexed tokenIn,
        uint256 amountDeposited,
        uint256 amountSyOut
    );

    /// @dev Emitted when any shares are redeemed for base tokens
    event Redeem(
        address indexed caller,
        address indexed receiver,
        address indexed tokenOut,
        uint256 amountSyToRedeem,
        uint256 amountTokenOut
    );

    /// @dev check `assetInfo()` for more information
    enum AssetType {
        TOKEN,
        LIQUIDITY
    }

    /**
     * @notice mints an amount of shares by depositing a base token.
     * @param receiver shares recipient address
     * @param tokenIn address of the base tokens to mint shares
     * @param amountTokenToDeposit amount of base tokens to be transferred from (`msg.sender`)
     * @param minSharesOut reverts if amount of shares minted is lower than this
     * @return amountSharesOut amount of shares minted
     * @dev Emits a {Deposit} event
     *
     * Requirements:
     * - (`tokenIn`) must be a valid base token.
     */
    function deposit(address receiver, address tokenIn, uint256 amountTokenToDeposit, uint256 minSharesOut)
        external
        payable
        returns (uint256 amountSharesOut);

    /**
     * @notice redeems an amount of base tokens by burning some shares
     * @param receiver recipient address
     * @param amountSharesToRedeem amount of shares to be burned
     * @param tokenOut address of the base token to be redeemed
     * @param minTokenOut reverts if amount of base token redeemed is lower than this
     * @param burnFromInternalBalance if true, burns from balance of `address(this)`, otherwise burns from `msg.sender`
     * @return amountTokenOut amount of base tokens redeemed
     * @dev Emits a {Redeem} event
     *
     * Requirements:
     * - (`tokenOut`) must be a valid base token.
     */
    function redeem(
        address receiver,
        uint256 amountSharesToRedeem,
        address tokenOut,
        uint256 minTokenOut,
        bool burnFromInternalBalance
    ) external returns (uint256 amountTokenOut);

    /**
     * @notice exchangeRate * syBalance / 1e18 must return the asset balance of the account
     * @dev Conversely, if a user contributes tokens worth X assets, the minted SY amount should be
     * derived via this same exchange rate. SYUtils's assetToSy and syToAsset helpers should be
     * preferred over raw multiplication and division.
     * @return res The current asset-per-SY exchange rate scaled by 1e18.
     */
    function exchangeRate() external view returns (uint256 res);

    /**
     * @notice returns the address of the yield-bearing Token
     * @dev This is the token contract held or interacted with by the SY implementation.
     * @return The configured yield-bearing token address.
     */
    function yieldBearingToken() external view returns (address);

    /**
     * @notice returns all tokens that can mint this SY
     * @dev Each returned token address is accepted by `deposit`.
     * @return res The list of supported deposit token addresses.
     */
    function getTokensIn() external view returns (address[] memory res);

    /**
     * @notice returns all tokens that can be redeemed by this SY
     * @dev Each returned token address is a supported redemption output.
     * @return res The list of supported redemption token addresses.
     */
    function getTokensOut() external view returns (address[] memory res);

    /**
     * @notice Returns whether `token` is accepted by `deposit`.
     * @dev This helper mirrors the token validation used by the SY implementation.
     * @param token The token to validate.
     * @return True when `token` is supported for deposits.
     */
    function isValidTokenIn(address token) external view returns (bool);

    /**
     * @notice Returns whether `token` is accepted by `redeem`.
     * @dev This helper mirrors the token validation used by the SY implementation.
     * @param token The token to validate.
     * @return True when `token` is supported for redemptions.
     */
    function isValidTokenOut(address token) external view returns (bool);

    /**
     * @notice Quotes shares minted for a deposit preview.
     * @dev The preview is expected to follow the same token validation rules as `deposit`.
     * @param tokenIn The token that would be deposited.
     * @param amountTokenToDeposit The amount of `tokenIn` to preview.
     * @return amountSharesOut The quoted share output.
     */
    function previewDeposit(address tokenIn, uint256 amountTokenToDeposit)
        external
        view
        returns (uint256 amountSharesOut);

    /**
     * @notice Quotes token output for a redemption preview.
     * @dev The preview is expected to follow the same token validation rules as `redeem`.
     * @param tokenOut The token that would be received.
     * @param amountSharesToRedeem The amount of shares to preview redeeming.
     * @return amountTokenOut The quoted redemption output.
     */
    function previewRedeem(address tokenOut, uint256 amountSharesToRedeem)
        external
        view
        returns (uint256 amountTokenOut);

    /// @notice Returns information used to interpret the canonical asset.
    /// @dev Consumers can use the returned tuple to understand the canonical asset exposed by the SY.
    /// @return assetType the type of the asset (0 for ERC20 tokens, 1 for AMM liquidity tokens,
    ///     2 for bridged yield bearing tokens like wstETH, rETH on Arbi whose the underlying asset doesn't exist on the chain)
    /// @return assetAddress the address of the asset
    /// @return assetDecimals the decimals of the asset
    function assetInfo() external view returns (AssetType assetType, address assetAddress, uint8 assetDecimals);
}
