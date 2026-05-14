// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

// OutrunTODO Delete the Ownable when the mainnet goes live
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IOutrunRouter} from "./interfaces/IOutrunRouter.sol";
import {IMemeverseLauncher} from "./interfaces/IMemeverseLauncher.sol";
import {IStandardizedYield} from "../yield/interfaces/IStandardizedYield.sol";
import {NativeAmountMismatch} from "../libraries/CommonErrors.sol";
import {IERC20, TokenHelper} from "../libraries/TokenHelper.sol";
import {IOutrunStakeManager} from "../position/interfaces/IOutrunStakeManager.sol";

contract OutrunRouter is IOutrunRouter, TokenHelper, Ownable {
    address public memeverseLauncher;

    constructor(address _owner, address _memeverseLauncher) Ownable(_owner) {
        memeverseLauncher = _memeverseLauncher;
    }

    /**
     * @notice Deposits an input token into a standardized yield contract.
     * @dev Always pulls `tokenIn` from the caller before forwarding the deposit into SY.
     * @param SY Standardized yield contract that receives the deposit.
     * @param tokenIn Token to supply when minting SY.
     * @param receiver Recipient of the minted SY.
     * @param amountInput Amount of input token to deposit.
     * @param minSyOut Minimum acceptable SY output.
     * @return amountInSYOut Amount of SY minted for `receiver`.
     */
    function mintSYFromToken(address SY, address tokenIn, address receiver, uint256 amountInput, uint256 minSyOut)
        external
        payable
        returns (uint256 amountInSYOut)
    {
        amountInSYOut = _mintSY(SY, tokenIn, receiver, amountInput, minSyOut);
    }

    /**
     * @notice Redeems standardized yield into an output token.
     * @dev Always pulls SY from the caller and burns it from SY internal balance during redemption.
     * @param SY Standardized yield contract being redeemed.
     * @param receiver Recipient of the redeemed token output.
     * @param tokenOut Token requested on redemption.
     * @param amountInSY Amount of SY to redeem.
     * @param minTokenOut Minimum acceptable token output.
     * @return amountInTokenOut Amount of `tokenOut` sent to `receiver`.
     */
    function redeemSyToToken(address SY, address receiver, address tokenOut, uint256 amountInSY, uint256 minTokenOut)
        external
        returns (uint256 amountInTokenOut)
    {
        amountInTokenOut = _redeemSy(SY, receiver, tokenOut, amountInSY, minTokenOut);
    }

    function _mintSY(address SY, address tokenIn, address receiver, uint256 amountInput, uint256 minSyOut)
        internal
        returns (uint256 amountInSYOut)
    {
        if (tokenIn != NATIVE && msg.value != 0) revert NativeAmountMismatch();

        _transferIn(tokenIn, msg.sender, amountInput);

        uint256 amountInNative = tokenIn == NATIVE ? amountInput : 0;
        _approveExact(tokenIn, SY, amountInput);
        amountInSYOut = IStandardizedYield(SY).deposit{value: amountInNative}(receiver, tokenIn, amountInput, minSyOut);
        _clearApproval(tokenIn, SY);
    }

    function _redeemSy(address SY, address receiver, address tokenOut, uint256 amountInSY, uint256 minTokenOut)
        internal
        returns (uint256 amountInRedeemed)
    {
        _transferFrom(IERC20(SY), msg.sender, SY, amountInSY);
        amountInRedeemed = IStandardizedYield(SY).redeem(receiver, amountInSY, tokenOut, minTokenOut, true);
    }

    /**
     * @notice Quotes the uAsset amount minted when staking from an input token.
     * @dev Derives canonical SY from `SP.SY()`, then uses the SY deposit preview and stake-manager preview.
     * @param SP Stake manager receiving the SY stake.
     * @param tokenIn Token to deposit into SY.
     * @param tokenAmount Amount of `tokenIn` to convert.
     * @param stakeParam Stake settings carried into the preview.
     * @return UAssetMintable Estimated uAsset minted by the stake flow.
     */
    function previewStakeFromToken(address SP, address tokenIn, uint256 tokenAmount, StakeParam calldata stakeParam)
        external
        view
        returns (uint256 UAssetMintable)
    {
        address SY = IOutrunStakeManager(SP).SY();
        uint256 amountInSY = IStandardizedYield(SY).previewDeposit(tokenIn, tokenAmount);
        UAssetMintable = IOutrunStakeManager(SP).previewStake(amountInSY);
        stakeParam.lockupDays;
    }

    /**
     * @notice Quotes the uAsset amount minted when staking existing SY.
     * @dev Reads the stake-manager preview for an SY-funded stake without changing state.
     * @param SP Stake manager receiving the SY stake.
     * @param amountInSY Amount of SY to stake.
     * @param stakeParam Stake settings carried into the preview.
     * @return UAssetMintable Estimated uAsset minted by the stake flow.
     */
    function previewStakeFromSY(address SP, uint256 amountInSY, StakeParam calldata stakeParam)
        external
        view
        returns (uint256 UAssetMintable)
    {
        UAssetMintable = IOutrunStakeManager(SP).previewStake(amountInSY);
        stakeParam.lockupDays;
    }

    /**
     * @notice Quotes the uAsset amount minted when wrap-staking from an input token.
     * @dev Derives canonical SY from `SP.SY()`, then combines the SY deposit preview with the wrap preview.
     * @param SP Stake manager receiving the wrapped stake.
     * @param tokenIn Token to deposit into SY.
     * @param tokenAmount Amount of `tokenIn` to convert.
     * @return UAssetMintable Estimated uAsset minted by the wrap-stake flow.
     */
    function previewWrapStakeFromToken(address SP, address tokenIn, uint256 tokenAmount)
        external
        view
        returns (uint256 UAssetMintable)
    {
        address SY = IOutrunStakeManager(SP).SY();
        uint256 amountInSY = IStandardizedYield(SY).previewDeposit(tokenIn, tokenAmount);
        UAssetMintable = IOutrunStakeManager(SP).previewWrapStake(amountInSY);
    }

    /**
     * @notice Deposits an input token, converts it into SY, and stakes it.
     * @dev Derives canonical SY from `SP.SY()`, mints it, and stakes on behalf of `stakeParam.owner`.
     * @param SP Stake manager receiving the SY stake.
     * @param tokenIn Token to deposit into SY.
     * @param tokenAmount Amount of `tokenIn` to convert and stake.
     * @param stakeParam Stake settings including lockup, slippage floor, and recipient.
     * @return positionId Newly created staking position id.
     * @return UAssetMinted Amount of uAsset minted for the stake.
     */
    function stakeFromToken(address SP, address tokenIn, uint256 tokenAmount, StakeParam calldata stakeParam)
        public
        payable
        returns (uint256 positionId, uint256 UAssetMinted)
    {
        address SY = IOutrunStakeManager(SP).SY();
        uint256 amountInSY = _mintSY(SY, tokenIn, address(this), tokenAmount, stakeParam.minSyOut);
        // receiver defaults to owner when not specified (address(0))
        address uAssetReceiver = stakeParam.receiver == address(0) ? stakeParam.owner : stakeParam.receiver;
        (positionId, UAssetMinted) =
            _stakeFromSYBalance(SY, SP, amountInSY, stakeParam.lockupDays, stakeParam.owner, uAssetReceiver);
        require(
            UAssetMinted >= stakeParam.minUAssetMinted,
            InsufficientUAssetMinted(UAssetMinted, stakeParam.minUAssetMinted)
        );
    }

    /**
     * @notice Stakes existing SY into the stake manager.
     * @dev Derives canonical SY from `SP.SY()` and pulls it into the router before staking.
     * @param SP Stake manager receiving the SY stake.
     * @param amountInSY Amount of SY to stake.
     * @param stakeParam Stake settings including lockup, slippage floor, and recipient.
     * @return positionId Newly created staking position id.
     * @return UAssetMinted Amount of uAsset minted for the stake.
     */
    function stakeFromSY(address SP, uint256 amountInSY, StakeParam calldata stakeParam)
        public
        returns (uint256 positionId, uint256 UAssetMinted)
    {
        address SY = IOutrunStakeManager(SP).SY();
        _transferFrom(IERC20(SY), msg.sender, address(this), amountInSY);
        // receiver defaults to owner when not specified (address(0))
        address uAssetReceiver = stakeParam.receiver == address(0) ? stakeParam.owner : stakeParam.receiver;
        (positionId, UAssetMinted) =
            _stakeFromSYBalance(SY, SP, amountInSY, stakeParam.lockupDays, stakeParam.owner, uAssetReceiver);
        require(
            UAssetMinted >= stakeParam.minUAssetMinted,
            InsufficientUAssetMinted(UAssetMinted, stakeParam.minUAssetMinted)
        );
    }

    /**
     * @notice Deposits an input token, converts it into SY, and wrap-stakes it.
     * @dev Mints SY into the router and immediately wrap-stakes into uAsset for `uAssetRecipient`.
     * @dev Derives SY from `SP.SY()`. SP owner is a fully trusted role across the system.
     * @param SP Stake manager receiving the wrapped stake.
     * @param tokenIn Token to deposit into SY.
     * @param tokenAmount Amount of `tokenIn` to convert and wrap-stake.
     * @param uAssetRecipient Recipient of the wrapped uAsset position.
     * @return UAssetMinted Amount of uAsset minted to `uAssetRecipient`.
     */
    function wrapStakeFromToken(
        address SP,
        address tokenIn,
        uint256 tokenAmount,
        uint256 minSyOut,
        address uAssetRecipient,
        uint256 minUAssetMinted
    ) public payable returns (uint256 UAssetMinted) {
        address SY = IOutrunStakeManager(SP).SY();
        uint256 amountInSY = _mintSY(SY, tokenIn, address(this), tokenAmount, minSyOut);

        _approveExact(SY, SP, amountInSY);
        UAssetMinted = IOutrunStakeManager(SP).wrapStake(amountInSY, uAssetRecipient);
        _clearApproval(SY, SP);
        require(UAssetMinted >= minUAssetMinted, InsufficientUAssetMinted(UAssetMinted, minUAssetMinted));
    }

    /**
     * @notice Wrap-stakes existing SY into uAsset.
     * @dev Derives canonical SY from `SP.SY()` and forwards it to the stake manager for wrap staking.
     * @param SP Stake manager receiving the wrapped stake.
     * @param amountInSY Amount of SY to wrap-stake.
     * @param uAssetRecipient Recipient of the minted uAsset.
     * @return UAssetMinted Amount of uAsset minted to `uAssetRecipient`.
     */
    function wrapStakeFromSY(address SP, uint256 amountInSY, address uAssetRecipient, uint256 minUAssetMinted)
        public
        returns (uint256 UAssetMinted)
    {
        address SY = IOutrunStakeManager(SP).SY();
        _transferFrom(IERC20(SY), msg.sender, address(this), amountInSY);

        _approveExact(SY, SP, amountInSY);
        UAssetMinted = IOutrunStakeManager(SP).wrapStake(amountInSY, uAssetRecipient);
        _clearApproval(SY, SP);
        require(UAssetMinted >= minUAssetMinted, InsufficientUAssetMinted(UAssetMinted, minUAssetMinted));
    }

    /**
     * @notice Quotes the token output from redeeming wrapped uAsset.
     * @dev Reads the stake-manager wrap-redeem preview without consuming uAsset.
     * @param SP Stake manager handling the wrap redemption.
     * @param amountInUAsset Amount of uAsset to redeem.
     * @param tokenOut Token requested on redemption.
     * @return amountTokenOut Estimated amount of `tokenOut` returned.
     */
    function previewWrapRedeem(address SP, uint256 amountInUAsset, address tokenOut)
        external
        view
        returns (uint256 amountTokenOut)
    {
        amountTokenOut = IOutrunStakeManager(SP).previewWrapRedeem(amountInUAsset, tokenOut);
    }

    function _stakeFromSYBalance(
        address SY,
        address SP,
        uint256 amountInSY,
        uint128 lockupDays,
        address positionOwner,
        address uAssetReceiver
    ) internal returns (uint256 positionId, uint256 UAssetMinted) {
        _approveExact(SY, SP, amountInSY);
        (positionId, UAssetMinted) =
            IOutrunStakeManager(SP).stake(amountInSY, lockupDays, positionOwner, uAssetReceiver);
        _clearApproval(SY, SP);
    }

    function _approveExact(address token, address spender, uint256 amount) internal {
        if (token == NATIVE) return;
        _safeApprove(token, spender, amount);
    }

    function _clearApproval(address token, address spender) internal {
        if (token == NATIVE) return;
        _safeApprove(token, spender, 0);
    }

    /**
     * @notice Redeems wrapped uAsset into an output token.
     * @dev Burns wrapped uAsset through the stake manager and forwards the redeemed token to `receiver`.
     * @param SP Stake manager handling the wrap redemption.
     * @param amountInUAsset Amount of uAsset to redeem.
     * @param receiver Recipient of the redeemed token output.
     * @param tokenOut Token requested on redemption.
     * @param minTokenOut Minimum acceptable token output from redemption.
     * @return amountTokenOut Amount of `tokenOut` sent to `receiver`.
     */
    function wrapRedeem(address SP, uint256 amountInUAsset, address receiver, address tokenOut, uint256 minTokenOut)
        external
        returns (uint256 amountTokenOut)
    {
        address uAsset = IOutrunStakeManager(SP).uAsset();
        _transferFrom(IERC20(uAsset), msg.sender, address(this), amountInUAsset);
        _approveExact(uAsset, SP, amountInUAsset);

        amountTokenOut = IOutrunStakeManager(SP).wrapRedeem(amountInUAsset, receiver, tokenOut, minTokenOut);
        _clearApproval(uAsset, SP);
    }

    /**
     * @notice Creates a genesis position starting from an input token.
     * @dev Mints and stakes through the router, then forwards the resulting uAsset amount into the launcher genesis flow.
     * @dev Derives SY from `SP.SY()`. SP owner is a fully trusted role across the system.
     * @param SP Stake manager receiving the genesis stake.
     * @param tokenIn Token to deposit into SY before staking.
     * @param tokenAmount Amount of `tokenIn` to convert and stake.
     * @param lockupDays Lockup duration forwarded to the stake manager.
     * @param verseId Memeverse verse identifier to launch against.
     * @param genesisUser User credited for the genesis position.
     */
    function genesisByToken(
        address SP,
        address tokenIn,
        uint256 tokenAmount,
        uint256 minSyOut,
        uint256 minUAssetMinted,
        uint128 lockupDays,
        uint256 verseId,
        address genesisUser
    ) external payable {
        address SY = IOutrunStakeManager(SP).SY();
        uint256 amountInSY = _mintSY(SY, tokenIn, address(this), tokenAmount, minSyOut);
        address uAsset = IOutrunStakeManager(SP).uAsset();
        (, uint256 amountInUAsset) = _stakeFromSYBalance(SY, SP, amountInSY, lockupDays, genesisUser, address(this));
        require(amountInUAsset >= minUAssetMinted, InsufficientUAssetMinted(amountInUAsset, minUAssetMinted));
        if (amountInUAsset > type(uint128).max) revert InvalidParam();
        _approveExact(uAsset, memeverseLauncher, amountInUAsset);
        // amountInUAsset is bounded by type(uint128).max immediately before this cast.
        // forge-lint: disable-next-line(unsafe-typecast)
        IMemeverseLauncher(memeverseLauncher).genesis(verseId, uint128(amountInUAsset), genesisUser);
        _clearApproval(uAsset, memeverseLauncher);
    }

    /**
     * @notice Creates a genesis position starting from existing SY.
     * @dev Derives canonical SY from `SP.SY()`, stakes it for `genesisUser`, then launches genesis.
     * @param SP Stake manager receiving the genesis stake.
     * @param amountInSY Amount of SY to stake for genesis.
     * @param lockupDays Lockup duration forwarded to the stake manager.
     * @param verseId Memeverse verse identifier to launch against.
     * @param genesisUser User credited for the genesis position.
     */
    function genesisBySY(
        address SP,
        uint128 amountInSY,
        uint128 lockupDays,
        uint256 verseId,
        address genesisUser,
        uint256 minUAssetMinted
    ) external {
        address SY = IOutrunStakeManager(SP).SY();
        _transferFrom(IERC20(SY), msg.sender, address(this), amountInSY);
        address uAsset = IOutrunStakeManager(SP).uAsset();
        (, uint256 amountInUAsset) = _stakeFromSYBalance(SY, SP, amountInSY, lockupDays, genesisUser, address(this));
        require(amountInUAsset >= minUAssetMinted, InsufficientUAssetMinted(amountInUAsset, minUAssetMinted));
        if (amountInUAsset > type(uint128).max) revert InvalidParam();
        _approveExact(uAsset, memeverseLauncher, amountInUAsset);
        // amountInUAsset is bounded by type(uint128).max immediately before this cast.
        // forge-lint: disable-next-line(unsafe-typecast)
        IMemeverseLauncher(memeverseLauncher).genesis(verseId, uint128(amountInUAsset), genesisUser);
        _clearApproval(uAsset, memeverseLauncher);
    }

    /**
     * @notice Updates the memeverse launcher address.
     * @dev Owner-only maintenance hook for the pre-mainnet launcher wiring. OutrunTODO: delete when mainnet goes live.
     * @param _memeverseLauncher New launcher contract address.
     */
    function setMemeverseLauncher(address _memeverseLauncher) external onlyOwner {
        memeverseLauncher = _memeverseLauncher;
    }
}
