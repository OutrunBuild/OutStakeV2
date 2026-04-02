// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

interface IOutrunRouter {
    struct StakeParam {
        uint128 lockupDays;
        uint256 minUAssetMinted;
        address owner;
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
        returns (uint256 amountInSYOut);

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
        returns (uint256 amountInTokenOut);

    /**
     * @notice Quotes the uAsset amount minted when staking from an input token.
     * @dev Uses the SY deposit preview and stake-manager preview without moving funds.
     * @param SY Standardized yield contract used for the initial deposit.
     * @param SP Stake manager receiving the SY stake.
     * @param tokenIn Token to deposit into SY.
     * @param tokenAmount Amount of `tokenIn` to convert.
     * @param stakeParam Stake settings carried into the preview.
     * @return UAssetMintable Estimated uAsset minted by the stake flow.
     */
    function previewStakeFromToken(
        address SY,
        address SP,
        address tokenIn,
        uint256 tokenAmount,
        StakeParam calldata stakeParam
    ) external view returns (uint256 UAssetMintable);

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
        returns (uint256 UAssetMintable);

    /**
     * @notice Quotes the uAsset amount minted when wrap-staking from an input token.
     * @dev Combines the SY deposit preview with the stake-manager wrap preview.
     * @param SY Standardized yield contract used for the initial deposit.
     * @param SP Stake manager receiving the wrapped stake.
     * @param tokenIn Token to deposit into SY.
     * @param tokenAmount Amount of `tokenIn` to convert.
     * @return UAssetMintable Estimated uAsset minted by the wrap-stake flow.
     */
    function previewWrapStakeFromToken(address SY, address SP, address tokenIn, uint256 tokenAmount)
        external
        view
        returns (uint256 UAssetMintable);

    /**
     * @notice Deposits an input token, converts it into SY, and stakes it.
     * @dev Pulls the input token into the router, mints SY, and stakes on behalf of `stakeParam.owner`.
     * @param SY Standardized yield contract used for the initial deposit.
     * @param SP Stake manager receiving the SY stake.
     * @param tokenIn Token to deposit into SY.
     * @param tokenAmount Amount of `tokenIn` to convert and stake.
     * @param stakeParam Stake settings including lockup, slippage floor, and recipient.
     * @return positionId Newly created staking position id.
     * @return UAssetMinted Amount of uAsset minted for the stake.
     */
    function stakeFromToken(
        address SY,
        address SP,
        address tokenIn,
        uint256 tokenAmount,
        StakeParam calldata stakeParam
    ) external payable returns (uint256 positionId, uint256 UAssetMinted);

    /**
     * @notice Stakes existing SY into the stake manager.
     * @dev Pulls SY into the router before staking on behalf of `stakeParam.owner`.
     * @param SY Standardized yield token being staked.
     * @param SP Stake manager receiving the SY stake.
     * @param amountInSY Amount of SY to stake.
     * @param stakeParam Stake settings including lockup, slippage floor, and recipient.
     * @return positionId Newly created staking position id.
     * @return UAssetMinted Amount of uAsset minted for the stake.
     */
    function stakeFromSY(address SY, address SP, uint256 amountInSY, StakeParam calldata stakeParam)
        external
        returns (uint256 positionId, uint256 UAssetMinted);

    /**
     * @notice Deposits an input token, converts it into SY, and wrap-stakes it.
     * @dev Mints SY into the router and immediately wrap-stakes into uAsset for `uAssetRecipient`.
     * @param SP Stake manager receiving the wrapped stake.
     * @param tokenIn Token to deposit into SY.
     * @param tokenAmount Amount of `tokenIn` to convert and wrap-stake.
     * @param uAssetRecipient Recipient of the wrapped uAsset position.
     * @return UAssetMinted Amount of uAsset minted to `uAssetRecipient`.
     */
    function wrapStakeFromToken(address SP, address tokenIn, uint256 tokenAmount, address uAssetRecipient)
        external
        payable
        returns (uint256 UAssetMinted);

    /**
     * @notice Wrap-stakes existing SY into uAsset.
     * @dev Pulls SY into the router and forwards it to the stake manager for wrap staking.
     * @param SY Standardized yield token being wrap-staked.
     * @param SP Stake manager receiving the wrapped stake.
     * @param amountInSY Amount of SY to wrap-stake.
     * @param uAssetRecipient Recipient of the minted uAsset.
     * @return UAssetMinted Amount of uAsset minted to `uAssetRecipient`.
     */
    function wrapStakeFromSY(address SY, address SP, uint256 amountInSY, address uAssetRecipient)
        external
        returns (uint256 UAssetMinted);

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
        returns (uint256 amountTokenOut);

    /**
     * @notice Redeems wrapped uAsset into an output token.
     * @dev Burns wrapped uAsset through the stake manager and forwards the redeemed token to `receiver`.
     * @param SP Stake manager handling the wrap redemption.
     * @param amountInUAsset Amount of uAsset to redeem.
     * @param receiver Recipient of the redeemed token output.
     * @param tokenOut Token requested on redemption.
     * @return amountTokenOut Amount of `tokenOut` sent to `receiver`.
     */
    function wrapRedeem(address SP, uint256 amountInUAsset, address receiver, address tokenOut)
        external
        returns (uint256 amountTokenOut);

    /**
     * @notice Creates a genesis position starting from an input token.
     * @dev Mints and stakes through the router, then forwards the resulting uAsset amount into the launcher genesis flow.
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
        uint128 lockupDays,
        uint256 verseId,
        address genesisUser
    ) external payable;

    /**
     * @notice Creates a genesis position starting from existing SY.
     * @dev Pulls SY into the router, stakes it for `genesisUser`, then launches genesis with the minted uAsset.
     * @param SY Standardized yield token being staked.
     * @param SP Stake manager receiving the genesis stake.
     * @param amountInSY Amount of SY to stake for genesis.
     * @param lockupDays Lockup duration forwarded to the stake manager.
     * @param verseId Memeverse verse identifier to launch against.
     * @param genesisUser User credited for the genesis position.
     */
    function genesisBySY(
        address SY,
        address SP,
        uint128 amountInSY,
        uint128 lockupDays,
        uint256 verseId,
        address genesisUser
    ) external;

    /**
     * @notice Updates the memeverse launcher address.
     * @dev Owner-only maintenance hook for the pre-mainnet launcher wiring.
     * @param memeverseLauncher New launcher contract address.
     */
    function setMemeverseLauncher(address memeverseLauncher) external;

    error InvalidParam();
    error InsufficientUAssetMinted(uint256 UAssetMinted, uint256 minMinted);
}
