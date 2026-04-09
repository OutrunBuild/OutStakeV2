// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {NativeAmountMismatch} from "../libraries/CommonErrors.sol";
import {TokenHelper} from "../libraries/TokenHelper.sol";
import {IStandardizedYield} from "./interfaces/IStandardizedYield.sol";
import {OutrunERC20, IERC20Metadata} from "../assets/base/OutrunERC20.sol";
import {OutrunERC20Pausable} from "../assets/base/OutrunERC20Pausable.sol";

/**
 * @dev Standardized Yield Base Contract
 */
abstract contract SYBase is IStandardizedYield, OutrunERC20Pausable, TokenHelper {
    address public immutable yieldBearingToken;

    constructor(string memory name_, string memory symbol_, address _yieldBearingToken, address _owner)
        OutrunERC20(name_, symbol_, IERC20Metadata(_yieldBearingToken).decimals())
        Ownable(_owner)
    {
        require(_yieldBearingToken != address(0), SYZeroAddress());

        yieldBearingToken = _yieldBearingToken;
    }

    receive() external payable {}

    /*///////////////////////////////////////////////////////////////
                DEPOSIT/REDEEM USING NATIVE YIELD TOKENS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Mints SY shares by depositing a supported base token.
     * @dev See {IStandardizedYield-deposit}
     * @param receiver The account receiving minted SY shares.
     * @param tokenIn The base token deposited into the SY.
     * @param amountTokenToDeposit The amount of `tokenIn` deposited.
     * @param minSharesOut The minimum acceptable share output.
     * @return amountSharesOut The amount of SY shares minted.
     */
    function deposit(address receiver, address tokenIn, uint256 amountTokenToDeposit, uint256 minSharesOut)
        external
        payable
        nonReentrant
        whenNotPaused
        returns (uint256 amountSharesOut)
    {
        require(isValidTokenIn(tokenIn), SYInvalidTokenIn(tokenIn));
        require(amountTokenToDeposit != 0, SYZeroDeposit());
        if (tokenIn != NATIVE && msg.value != 0) revert NativeAmountMismatch();

        _transferIn(tokenIn, msg.sender, amountTokenToDeposit);

        amountSharesOut = _deposit(tokenIn, amountTokenToDeposit);
        require(amountSharesOut >= minSharesOut, SYInsufficientSharesOut(amountSharesOut, minSharesOut));

        _mint(receiver, amountSharesOut);
        emit Deposit(msg.sender, receiver, tokenIn, amountTokenToDeposit, amountSharesOut);
    }

    /**
     * @notice Redeems SY shares into a supported output token.
     * @dev See {IStandardizedYield-redeem}
     * @param receiver The account receiving redeemed tokens.
     * @param amountSharesToRedeem The amount of SY shares to burn.
     * @param tokenOut The base token requested on redemption.
     * @param minTokenOut The minimum acceptable token output.
     * @param burnFromInternalBalance Whether to burn shares from `address(this)` instead of `msg.sender`.
     * @return amountTokenOut The amount of output tokens redeemed.
     */
    function redeem(
        address receiver,
        uint256 amountSharesToRedeem,
        address tokenOut,
        uint256 minTokenOut,
        bool burnFromInternalBalance
    ) external nonReentrant whenNotPaused returns (uint256 amountTokenOut) {
        require(isValidTokenOut(tokenOut), SYInvalidTokenOut(tokenOut));
        require(amountSharesToRedeem != 0, SYZeroRedeem());
        amountTokenOut = _redeem(receiver, tokenOut, amountSharesToRedeem);

        if (burnFromInternalBalance) {
            _burn(address(this), amountSharesToRedeem);
        } else {
            _burn(msg.sender, amountSharesToRedeem);
        }

        require(amountTokenOut >= minTokenOut, SYInsufficientTokenOut(amountTokenOut, minTokenOut));

        emit Redeem(msg.sender, receiver, tokenOut, amountSharesToRedeem, amountTokenOut);
    }

    /**
     * @notice mint shares based on the deposited base tokens
     * @param tokenIn base token address used to mint shares
     * @param amountDeposited amount of base tokens deposited
     * @return amountSharesOut amount of shares minted
     */
    function _deposit(address tokenIn, uint256 amountDeposited) internal virtual returns (uint256 amountSharesOut);

    /**
     * @notice redeems base tokens based on amount of shares to be burned
     * @param tokenOut address of the base token to be redeemed
     * @param amountSharesToRedeem amount of shares to be burned
     * @return amountTokenOut amount of base tokens redeemed
     */
    function _redeem(address receiver, address tokenOut, uint256 amountSharesToRedeem)
        internal
        virtual
        returns (uint256 amountTokenOut);

    /*///////////////////////////////////////////////////////////////
                               EXCHANGE-RATE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the current asset-per-share exchange rate for this SY.
     * @dev See {IStandardizedYield-exchangeRate}
     * @return res The current exchange rate scaled by `1e18`.
     */
    function exchangeRate() external view virtual override returns (uint256 res);

    /*///////////////////////////////////////////////////////////////
                MISC METADATA FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Quotes the shares minted for depositing `amountTokenToDeposit` of `tokenIn`.
     * @dev Mirrors the token validation used by `deposit`.
     * @param tokenIn The token that would be deposited.
     * @param amountTokenToDeposit The amount of `tokenIn` to preview.
     * @return amountSharesOut The quoted share output.
     */
    function previewDeposit(address tokenIn, uint256 amountTokenToDeposit)
        external
        view
        virtual
        returns (uint256 amountSharesOut)
    {
        require(isValidTokenIn(tokenIn), SYInvalidTokenIn(tokenIn));
        return _previewDeposit(tokenIn, amountTokenToDeposit);
    }

    /**
     * @notice Quotes the token output for redeeming `amountSharesToRedeem` into `tokenOut`.
     * @dev Mirrors the token validation used by `redeem`.
     * @param tokenOut The token that would be received.
     * @param amountSharesToRedeem The amount of shares to preview redeeming.
     * @return amountTokenOut The quoted redemption output.
     */
    function previewRedeem(address tokenOut, uint256 amountSharesToRedeem)
        external
        view
        virtual
        returns (uint256 amountTokenOut)
    {
        require(isValidTokenOut(tokenOut), SYInvalidTokenOut(tokenOut));
        return _previewRedeem(tokenOut, amountSharesToRedeem);
    }

    function _previewDeposit(address tokenIn, uint256 amountTokenToDeposit)
        internal
        view
        virtual
        returns (uint256 amountSharesOut);

    function _previewRedeem(address tokenOut, uint256 amountSharesToRedeem)
        internal
        view
        virtual
        returns (uint256 amountTokenOut);

    /**
     * @notice Returns all tokens accepted by `deposit`.
     * @dev Mirrors the token universe checked by `isValidTokenIn`.
     * @return res The supported deposit token list.
     */
    function getTokensIn() public view virtual returns (address[] memory res);

    /**
     * @notice Returns all tokens produced by `redeem`.
     * @dev Mirrors the token universe checked by `isValidTokenOut`.
     * @return res The supported redemption token list.
     */
    function getTokensOut() public view virtual returns (address[] memory res);

    /**
     * @notice Returns whether `token` is accepted by `deposit`.
     * @dev Implementations should keep this helper consistent with `getTokensIn`.
     * @param token The token to validate.
     * @return True when `token` is supported for deposits.
     */
    function isValidTokenIn(address token) public view virtual returns (bool);

    /**
     * @notice Returns whether `token` is accepted by `redeem`.
     * @dev Implementations should keep this helper consistent with `getTokensOut`.
     * @param token The token to validate.
     * @return True when `token` is supported for redemptions.
     */
    function isValidTokenOut(address token) public view virtual returns (bool);
}
