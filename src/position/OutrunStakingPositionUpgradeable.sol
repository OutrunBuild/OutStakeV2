// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {IOutrunStakeManager} from "./interfaces/IOutrunStakeManager.sol";
import {IStandardizedYield} from "../yield/interfaces/IStandardizedYield.sol";
import {IUniversalAssets} from "../assets/interfaces/IUniversalAssets.sol";
import {SYUtils} from "../libraries/SYUtils.sol";
import {TokenHelper} from "../libraries/TokenHelper.sol";
import {AutoIncrementIdUpgradeable} from "../libraries/AutoIncrementIdUpgradeable.sol";

/// @notice OutrunStakingPosition manages two staking paths:
/// (a) locked positions with ids and deadlines, and
/// (b) a shared wrap pool with no per-user records.
/// SY = Standardized Yield token.
/// uAsset = universal asset receipt token.
/// The contract converts between SY and uAsset using the SY's exchange rate,
/// then rescales across decimal domains.
contract OutrunStakingPositionUpgradeable is
    IOutrunStakeManager,
    AutoIncrementIdUpgradeable,
    TokenHelper,
    PausableUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    /// @custom:storage-location erc7201:outrun.storage.OutrunStakingPosition
    struct OutrunStakingPositionStorage {
        address SY;
        uint256 minStake;
        uint256 syTotalStaking;
        uint256 syWrapStaking;
        uint256 wrapUAssetDebt;
        address uAsset;
        address revenuePool;
        address keeper;
        mapping(uint256 positionId => Position) positions;
        uint8 canonicalAssetDecimals;
        uint8 uAssetDecimals;
    }

    // keccak256(abi.encode(uint256(keccak256("outrun.storage.OutrunStakingPosition")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant OUTRUN_STAKING_POSITION_STORAGE_LOCATION =
        0xd6ebf98633cd133425e2ec4f5c3d5a1e15a1a3a82505bb0f6ed101932bed5200;

    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the staking position contract with required parameters.
    /// Conversion math assumes SY assetInfo() and uAsset decimals are immutable after initialization.
    /// @param owner_ Owner address for the Ownable access-control module.
    /// @param minStake_ Minimum SY amount per stake operation.
    /// @param revenuePool_ Address that receives harvested wrap-pool yield.
    /// @param sy_ Address of the Standardized Yield token accepted by this contract.
    /// @param uAsset_ Address of the universal asset receipt token.
    /// @param keeper_ Address authorized to call keepRedeem on matured positions.
    function initialize(
        address owner_,
        uint256 minStake_,
        address revenuePool_,
        address sy_,
        address uAsset_,
        address keeper_
    ) external initializer {
        if (
            owner_ == address(0) || revenuePool_ == address(0) || sy_ == address(0) || uAsset_ == address(0)
                || keeper_ == address(0)
        ) {
            revert ZeroInput();
        }
        __AutoIncrementId_init();
        __Pausable_init();
        __Ownable_init(owner_);
        __UUPSUpgradeable_init();

        OutrunStakingPositionStorage storage $ = _getStorage();
        (,, uint8 canonicalAssetDecimals) = IStandardizedYield(sy_).assetInfo();
        $.SY = sy_;
        $.uAsset = uAsset_;
        // Conversion math assumes SY assetInfo() and uAsset decimals are immutable after initialization.
        $.canonicalAssetDecimals = canonicalAssetDecimals;
        $.uAssetDecimals = IERC20Metadata(uAsset_).decimals();
        $.minStake = minStake_;
        $.revenuePool = revenuePool_;
        $.keeper = keeper_;
    }

    function _getStorage() private pure returns (OutrunStakingPositionStorage storage $) {
        // slither-disable-next-line assembly
        assembly {
            $.slot := OUTRUN_STAKING_POSITION_STORAGE_LOCATION
        }
    }

    // solhint-disable-next-line unwrapped-modifier-logic
    modifier onlyPositionOwner(uint256 positionId) {
        Position storage position = _getStorage().positions[positionId];
        // Only the recorded owner can act on this position.
        if (position.owner == address(0) || position.owner != msg.sender) revert PositionAccessDenied();
        _;
    }

    /// @notice Returns the Standardized Yield token address.
    /// @return SY token address.
    function SY() public view returns (address) {
        return _getStorage().SY;
    }

    /// @notice Returns the minimum SY amount required per stake operation.
    /// @return Minimum stake amount in SY.
    function minStake() public view returns (uint256) {
        return _getStorage().minStake;
    }

    /// @notice Returns the total SY staked across all positions and the wrap pool.
    /// @return Total SY staked.
    function syTotalStaking() public view returns (uint256) {
        return _getStorage().syTotalStaking;
    }

    /// @notice Returns the SY amount currently in the shared wrap pool.
    /// @return SY amount in the wrap pool.
    function syWrapStaking() public view returns (uint256) {
        return _getStorage().syWrapStaking;
    }

    /// @notice Returns the outstanding uAsset debt incurred by the wrap pool.
    /// @return Wrap pool uAsset debt.
    function wrapUAssetDebt() public view returns (uint256) {
        return _getStorage().wrapUAssetDebt;
    }

    /// @notice Returns the universal asset receipt token address.
    /// @return uAsset token address.
    function uAsset() public view returns (address) {
        return _getStorage().uAsset;
    }

    /// @notice Returns the revenue pool address that receives harvested yield.
    /// @return Revenue pool address.
    function revenuePool() public view returns (address) {
        return _getStorage().revenuePool;
    }

    /// @notice Returns the keeper address authorized to trigger position redemptions.
    /// @return Keeper address.
    function keeper() public view returns (address) {
        return _getStorage().keeper;
    }

    /// @notice Reads the stored position struct for a given position ID.
    /// @param positionId The position identifier.
    /// @return owner Position owner address.
    /// @return syStaked SY amount currently staked in the position.
    /// @return UAssetMinted uAsset amount minted against this position.
    /// @return startTime Timestamp when the position was created.
    /// @return deadline Timestamp after which the position can be redeemed.
    function positions(uint256 positionId)
        public
        view
        returns (address owner, uint256 syStaked, uint256 UAssetMinted, uint128 startTime, uint128 deadline)
    {
        Position storage position = _getStorage().positions[positionId];
        return (position.owner, position.syStaked, position.UAssetMinted, position.startTime, position.deadline);
    }

    /// @notice Previews the uAsset amount mintable from a given SY stake amount.
    /// Rounds down.
    /// @param amountInSY The SY amount to stake.
    /// @return UAssetMintable uAsset amount that would be minted.
    function previewStake(uint256 amountInSY) external view returns (uint256 UAssetMintable) {
        _validateMinStake(amountInSY);
        UAssetMintable = _syToAsset(amountInSY);
    }

    /// @notice Previews the uAsset amount mintable from a given SY amount for a wrap stake.
    /// Rounds down.
    /// @param amountInSY The SY amount to wrap stake.
    /// @return UAssetMintable uAsset amount that would be minted.
    function previewWrapStake(uint256 amountInSY) external view returns (uint256 UAssetMintable) {
        if (amountInSY == 0) revert ZeroInput();
        UAssetMintable = _syToAsset(amountInSY);
    }

    /// @notice Previews additional uAsset drawable from a position based on accrued yield.
    /// Returns 0 if current value has not exceeded previously minted amounts.
    /// @param positionId The position identifier.
    /// @return UAssetMintable Additional uAsset amount that can be drawn.
    function previewDrawUAsset(uint256 positionId) public view returns (uint256 UAssetMintable) {
        Position storage position = _getStorage().positions[positionId];
        if (position.owner == address(0)) revert PositionAccessDenied();
        uint256 currentValue = _syToAsset(position.syStaked);
        uint256 minted = position.UAssetMinted;
        if (currentValue <= minted) return 0;
        UAssetMintable = currentValue - minted;
    }

    /// @notice Previews the outcome of redeeming SY from a matured position.
    /// Partial redeem debt uses ceil rounding so redeemed SY cannot leave rounded debt dust on the remaining position.
    /// Full redeem burns all remaining debt exactly.
    /// @param positionId The position identifier.
    /// @param syRedeemed Amount of SY to redeem from the position.
    /// @param tokenOut Desired output token address (SY itself or another token via SY.redeem).
    /// @return UAssetBurned uAsset amount that would be burned.
    /// @return amountTokenOut Amount of tokenOut that would be received.
    function previewRedeem(uint256 positionId, uint256 syRedeemed, address tokenOut)
        public
        view
        returns (uint256 UAssetBurned, uint256 amountTokenOut)
    {
        Position storage position = _getStorage().positions[positionId];
        if (position.owner == address(0)) revert PositionAccessDenied();
        _validateRedeemAmount(position.syStaked, syRedeemed);

        // Partial redeem debt uses ceil so redeemed SY cannot leave rounded debt dust on the remaining position.
        UAssetBurned = _computeRedeemPositionDebt(position.UAssetMinted, syRedeemed, position.syStaked);
        amountTokenOut = _previewTokenOut(SY(), tokenOut, syRedeemed);
    }

    /// @notice Previews the tokenOut received when redeeming uAsset from the wrap pool.
    /// Uses floor conversion from uAsset to SY. Reverts when amountInUAsset is 0.
    /// @param amountInUAsset uAsset amount to redeem from the wrap pool.
    /// @param tokenOut Desired output token address (SY itself or another token via SY.redeem).
    /// @return amountTokenOut Amount of tokenOut that would be received.
    function previewWrapRedeem(uint256 amountInUAsset, address tokenOut) public view returns (uint256 amountTokenOut) {
        if (amountInUAsset == 0) revert ZeroInput();
        uint256 amountInSY = _assetToSy(amountInUAsset);
        amountTokenOut = _previewTokenOut(SY(), tokenOut, amountInSY);
    }

    /// @notice Stakes SY tokens and creates a time-locked position, minting uAsset to the receiver.
    /// Rounds down when converting SY to uAsset to avoid over-minting.
    /// @dev The position is locked until deadline (startTime + lockupDays * 1 day).
    /// Redeeming the staked SY requires the deadline to have passed.
    /// @param amountInSY SY amount to stake. Must be >= minStake.
    /// @param lockupDays Number of days the position is locked after creation.
    /// @param positionOwner Address that will own the position and can draw/redeem it.
    /// @param uAssetReceiver Address that receives the minted uAsset.
    /// @return positionId The newly created position identifier.
    /// @return UAssetMinted The uAsset amount minted for this stake.
    function stake(uint256 amountInSY, uint128 lockupDays, address positionOwner, address uAssetReceiver)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 positionId, uint256 UAssetMinted)
    {
        if (positionOwner == address(0) || uAssetReceiver == address(0)) revert ZeroInput();
        address _SY = SY();
        address _uAsset = uAsset();
        // Step 1: validate minimum stake amount.
        _validateMinStake(amountInSY);
        // Step 2: pull SY tokens from the staker.
        _transferIn(_SY, msg.sender, amountInSY);

        // Step 3: convert SY principal to uAsset value at the current exchange rate.
        uint256 principalValue = _syToAsset(amountInSY);
        // Step 4: check that uAsset mint cap is not exceeded.
        _checkUAssetMintCap(_uAsset, principalValue);

        OutrunStakingPositionStorage storage $ = _getStorage();
        unchecked {
            $.syTotalStaking += amountInSY;
        }

        // Step 5: create a new position with lockup deadline.
        positionId = _nextId();
        UAssetMinted = principalValue;
        $.positions[positionId] = Position({
            owner: positionOwner,
            syStaked: amountInSY,
            UAssetMinted: UAssetMinted,
            startTime: uint128(block.timestamp),
            // slither-disable-next-line timestamp
            deadline: uint128(block.timestamp + lockupDays * 1 days)
        });

        // Step 6: mint uAsset to the designated receiver.
        IUniversalAssets(_uAsset).mint(uAssetReceiver, UAssetMinted);
        emit Stake(
            positionId, positionOwner, amountInSY, principalValue, UAssetMinted, $.positions[positionId].deadline
        );
    }

    /// @notice Mints extra uAsset from a position after the staked SY becomes more valuable.
    /// Only the position owner can call this. Reverts if the position has no extra value to mint against.
    /// @param positionId The position identifier.
    /// @param recipient Address that receives the newly minted uAsset.
    /// @return amountInUAsset Additional uAsset amount minted.
    function drawUAsset(uint256 positionId, address recipient)
        external
        onlyPositionOwner(positionId)
        nonReentrant
        whenNotPaused
        returns (uint256 amountInUAsset)
    {
        if (recipient == address(0)) revert ZeroInput();
        amountInUAsset = previewDrawUAsset(positionId);
        if (amountInUAsset == 0) revert NothingToDraw();

        Position storage position = _getStorage().positions[positionId];
        // Increase the position debt first so the newly minted uAsset is recorded against this position.
        position.UAssetMinted += amountInUAsset;

        address _uAsset = uAsset();
        // The global minter cap protects total uAsset minted by this stake manager.
        _checkUAssetMintCap(_uAsset, amountInUAsset);
        IUniversalAssets(_uAsset).mint(recipient, amountInUAsset);
        emit DrawUAsset(positionId, recipient, amountInUAsset);
    }

    /// @notice Stakes SY into the shared wrap pool without creating a position, minting uAsset immediately.
    /// No lockup period applies; the caller can wrapRedeem at any time.
    /// Rounds down when converting SY to uAsset to avoid over-minting.
    /// @dev Increments both syTotalStaking and syWrapStaking, and also increments wrapUAssetDebt.
    /// @param amountInSY SY amount to wrap stake. Must be > 0.
    /// @param uAssetRecipient Address that receives the minted uAsset.
    /// @return UAssetAmount uAsset amount minted.
    function wrapStake(uint256 amountInSY, address uAssetRecipient)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 UAssetAmount)
    {
        if (uAssetRecipient == address(0) || amountInSY == 0) revert ZeroInput();
        address _SY = SY();
        address _uAsset = uAsset();
        // The shared wrap pool receives SY directly from the caller; no position owner or deadline is stored.
        _transferIn(_SY, msg.sender, amountInSY);

        // Minted uAsset is tracked as shared pool debt, not position-specific debt.
        uint256 principalValue = _syToAsset(amountInSY);
        _checkUAssetMintCap(_uAsset, principalValue);

        OutrunStakingPositionStorage storage $ = _getStorage();
        unchecked {
            $.syTotalStaking += amountInSY;
            $.syWrapStaking += amountInSY;
            $.wrapUAssetDebt += principalValue;
        }

        UAssetAmount = principalValue;
        IUniversalAssets(_uAsset).mint(uAssetRecipient, UAssetAmount);
        emit WrapStake(amountInSY, UAssetAmount, uAssetRecipient);
    }

    // slither-disable-next-line reentrancy-no-eth,timestamp
    /// @notice Redeems SY from a matured position, repaying uAsset debt and sending tokenOut to the receiver.
    /// Only the position owner can call. The position deadline must have passed.
    /// @dev Debt is repaid proportionally: if all SY is redeemed, all remaining uAsset debt is burned.
    /// Partial redeems use ceil rounding for debt so no stranded debt remains on the position.
    /// Direct SY tokenOut bypasses the SY.redeem fee route; all other tokenOut paths go through SY.redeem.
    /// @param positionId The position identifier.
    /// @param syRedeemed Amount of SY to redeem from the position.
    /// @param receiver Address that receives the tokenOut.
    /// @param tokenOut Desired output token (SY itself or another token via SY.redeem).
    /// @param minTokenOut Minimum acceptable amount of tokenOut (slippage protection).
    /// @return UAssetBurned uAsset amount burned as debt repayment.
    /// @return amountTokenOut Amount of tokenOut sent to the receiver.
    function redeem(uint256 positionId, uint256 syRedeemed, address receiver, address tokenOut, uint256 minTokenOut)
        external
        onlyPositionOwner(positionId)
        nonReentrant
        whenNotPaused
        returns (uint256 UAssetBurned, uint256 amountTokenOut)
    {
        if (receiver == address(0)) revert ZeroInput();
        address _SY = SY();
        // Matured position debt is computed before any state change so the burn amount is deterministic.
        UAssetBurned = _previewRedeemPositionDebt(positionId, syRedeemed);
        // Direct SY redemption bypasses SY.redeem, so enforce minTokenOut here.
        if (tokenOut == _SY && syRedeemed < minTokenOut) revert InsufficientTokenOut(syRedeemed, minTokenOut);
        // Burn the required uAsset debt and reduce or delete the position.
        Position storage position = _getStorage().positions[positionId];
        // Repay burns uAsset from the caller and reduces this stake manager's outstanding mint debt.
        IUniversalAssets(uAsset()).repay(msg.sender, UAssetBurned);
        _applyPositionRedeem(positionId, position, syRedeemed, UAssetBurned);
        // Release SY directly or redeem through the SY adapter into tokenOut.
        amountTokenOut = _redeemTokenOut(_SY, receiver, tokenOut, syRedeemed, minTokenOut);

        emit Redeem(positionId, msg.sender, syRedeemed, UAssetBurned, receiver, tokenOut, amountTokenOut);
    }

    // slither-disable-next-line reentrancy-no-eth
    /// @notice Redeems uAsset from the wrap pool, repaying uAsset debt to release SY and send tokenOut to the receiver.
    /// Anyone can call; no position ownership is required. Amount must not exceed wrapUAssetDebt.
    /// @dev Floor conversion from uAsset to SY ensures the wrap pool never releases more SY than the repaid debt accounts for.
    /// Checks that syWrapStaking holds enough SY to cover the release. Overflows are prevented by the debt ceiling check.
    /// Direct SY tokenOut sends SY to the receiver without a redemption fee; all other tokenOut paths go through SY.redeem.
    /// @param amountInUAsset uAsset amount to redeem. Must be > 0 and <= wrapUAssetDebt.
    /// @param receiver Address that receives the tokenOut.
    /// @param tokenOut Desired output token (SY itself or another token via SY.redeem).
    /// @param minTokenOut Minimum acceptable amount of tokenOut (slippage protection).
    /// @return amountTokenOut Amount of tokenOut sent to the receiver.
    function wrapRedeem(uint256 amountInUAsset, address receiver, address tokenOut, uint256 minTokenOut)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 amountTokenOut)
    {
        if (receiver == address(0) || amountInUAsset == 0) revert ZeroInput();
        OutrunStakingPositionStorage storage $ = _getStorage();
        if (amountInUAsset > $.wrapUAssetDebt) revert ErrorInput();

        address _SY = SY();
        address _uAsset = uAsset();
        // Floor conversion: wrapRedeem never releases more SY than the repaid debt accounts for.
        uint256 amountInSY = _assetToSy(amountInUAsset);
        // Check that the wrap pool holds enough SY to cover the release.
        if (amountInSY > $.syWrapStaking) revert ExceedsWrapPoolBalance(amountInSY, $.syWrapStaking);

        IUniversalAssets(_uAsset).repay(msg.sender, amountInUAsset);

        unchecked {
            $.syTotalStaking -= amountInSY;
            $.syWrapStaking -= amountInSY;
            $.wrapUAssetDebt -= amountInUAsset;
        }

        // If tokenOut is SY itself, send SY directly — no redemption fee is incurred.
        if (tokenOut == _SY) {
            if (amountInSY < minTokenOut) revert InsufficientTokenOut(amountInSY, minTokenOut);
            amountTokenOut = amountInSY;
            _transferSY(receiver, amountInSY);
        } else {
            // Otherwise, redeem SY through the SY contract into the desired token.
            amountTokenOut = IStandardizedYield(_SY).redeem(receiver, amountInSY, tokenOut, minTokenOut, false);
        }

        emit WrapRedeem(receiver, amountInUAsset, amountTokenOut, tokenOut);
    }

    // slither-disable-next-line reentrancy-no-eth,timestamp
    /// @notice Keeper burns uAsset to trigger redemption of a matured position.
    /// Debt-equivalent SY goes to receiver; any excess SY above debt goes back to position owner.
    function keepRedeem(uint256 positionId, uint256 amountInUAsset, address receiver)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 UAssetBurned, uint256 keeperPrincipalSY, uint256 ownerExcessSY)
    {
        // Keeper-only entrypoint guard.
        if (msg.sender != keeper()) revert PermissionDenied();
        if (receiver == address(0)) revert ZeroInput();
        address _uAsset = uAsset();
        Position storage position = _getStorage().positions[positionId];
        address positionOwner = position.owner;
        if (positionOwner == address(0)) revert PositionAccessDenied();
        uint128 deadline = position.deadline;
        if (block.timestamp < deadline) revert LockTimeNotExpired(deadline);

        uint256 syStaked = position.syStaked;
        uint256 positionUAssetMinted = position.UAssetMinted;
        if (amountInUAsset == 0) revert ZeroInput();
        if (amountInUAsset > positionUAssetMinted) revert ErrorInput();

        // Step 1: burn uAsset from the caller (keeper provides uAsset).
        UAssetBurned = amountInUAsset;
        IUniversalAssets(_uAsset).repay(msg.sender, UAssetBurned);

        // Step 2: convert burned uAsset to SY at the current exchange rate (keeperPrincipalSY).
        // Step 3: compute the proportional SY share of the redeemed debt (syRedeemed = syStaked * burnedUAsset / totalDebt).
        // Step 4: clamp keeperPrincipalSY so it never exceeds the proportional SY redeemed.
        keeperPrincipalSY = _assetToSy(UAssetBurned);
        uint256 syRedeemed = Math.mulDiv(syStaked, amountInUAsset, positionUAssetMinted);
        if (keeperPrincipalSY > syRedeemed) keeperPrincipalSY = syRedeemed;
        // Step 5: the position owner receives any remaining SY above the keeper's share.
        ownerExcessSY = syRedeemed - keeperPrincipalSY;

        // Step 6: apply position reduction and transfer SY to both parties.
        _applyPositionRedeem(positionId, position, syRedeemed, UAssetBurned);
        _transferSY(receiver, keeperPrincipalSY);
        _transferSY(positionOwner, ownerExcessSY);

        emit KeepRedeem(positionId, positionOwner, syRedeemed, UAssetBurned, receiver, keeperPrincipalSY, ownerExcessSY);
    }

    function harvestWrapYield(address tokenOut, uint256 minTokenOut)
        external
        onlyOwner
        nonReentrant
        whenNotPaused
        returns (uint256 amountTokenOut)
    {
        OutrunStakingPositionStorage storage $ = _getStorage();
        uint256 wrapPoolSY = $.syWrapStaking;
        // Ceil conversion: only SY above the full debt-equivalent is harvestable.
        // Rounding up the debt means enough SY stays in the wrap pool to cover all remaining debt.
        uint256 wrapDebtInSY = _assetToSyUp($.wrapUAssetDebt);
        // If no excess SY exists, return 0 without reverting.
        if (wrapPoolSY <= wrapDebtInSY) return 0;

        uint256 amountInSY = wrapPoolSY - wrapDebtInSY;
        address _SY = SY();
        unchecked {
            // Harvesting removes only excess SY; the wrap debt-equivalent amount stays in the pool.
            $.syTotalStaking -= amountInSY;
            $.syWrapStaking -= amountInSY;
        }

        if (tokenOut == _SY) {
            // Direct SY payout avoids adapter redemption and therefore needs its own minTokenOut check.
            if (amountInSY < minTokenOut) revert InsufficientTokenOut(amountInSY, minTokenOut);
            amountTokenOut = amountInSY;
            _transferSY($.revenuePool, amountInSY);
        } else {
            // Non-SY payout converts excess SY through the adapter and sends proceeds to revenuePool.
            amountTokenOut = IStandardizedYield(_SY).redeem($.revenuePool, amountInSY, tokenOut, minTokenOut, false);
        }

        emit HarvestWrapYield($.revenuePool, tokenOut, amountInSY, amountTokenOut);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setMinStake(uint256 minStake_) external onlyOwner {
        _getStorage().minStake = minStake_;
        emit SetMinStake(minStake_);
    }

    function setRevenuePool(address revenuePool_) external onlyOwner {
        if (revenuePool_ == address(0)) revert ZeroInput();
        _getStorage().revenuePool = revenuePool_;
        emit SetRevenuePool(revenuePool_);
    }

    function setKeeper(address keeper_) external onlyOwner {
        if (keeper_ == address(0)) revert ZeroInput();
        _getStorage().keeper = keeper_;
        emit SetKeeper(keeper_);
    }

    function _validateMinStake(uint256 amountInSY) internal view {
        uint256 minStake_ = minStake();
        if (amountInSY < minStake_) revert MinStakeInsufficient(minStake_);
    }

    function _checkUAssetMintCap(address _uAsset, uint256 amount) internal view {
        if (IUniversalAssets(_uAsset).checkMintableAmount(address(this)) < amount) {
            revert UAssetMintingCapReached();
        }
    }

    // `canonicalAssetValue` follows `SY.assetInfo().assetDecimals`.
    // `uAssetDebtUnits` follows `uAsset.decimals()`.
    // These helpers first convert via `SY.exchangeRate()` and then rescale across the two decimal domains.

    /// @dev Used for stake/draw — minting uAsset against SY principal. Rounds down to avoid over-minting.
    function _syToAsset(uint256 amountInSY) internal view returns (uint256) {
        address _SY = SY();
        uint256 canonicalAssetValue = SYUtils.syToAsset(IStandardizedYield(_SY).exchangeRate(), amountInSY);
        return _scaleCanonicalAssetToUAsset(canonicalAssetValue);
    }

    /// @dev Used for wrap redeem — converting uAsset debt back to SY to release. Rounds down to avoid releasing too much SY.
    function _assetToSy(uint256 amountInAsset) internal view returns (uint256) {
        address _SY = SY();
        uint256 canonicalAssetValue = _scaleUAssetToCanonicalAsset(amountInAsset, Math.Rounding.Floor);
        return SYUtils.assetToSy(IStandardizedYield(_SY).exchangeRate(), canonicalAssetValue);
    }

    /// @dev Used for harvest — computing debt in SY terms. Rounds up to leave enough SY covering all debt.
    function _assetToSyUp(uint256 amountInAsset) internal view returns (uint256) {
        address _SY = SY();
        uint256 canonicalAssetValue = _scaleUAssetToCanonicalAsset(amountInAsset, Math.Rounding.Ceil);
        return SYUtils.assetToSyUp(IStandardizedYield(_SY).exchangeRate(), canonicalAssetValue);
    }

    /// @dev Rescales from canonical asset decimals (e.g. 18 for ETH) to uAsset decimals (e.g. 6 for USDC-denominated uAsset).
    function _scaleCanonicalAssetToUAsset(uint256 amount) internal view returns (uint256) {
        (uint8 canonicalAssetDecimals, uint8 uAssetDecimals) = _cachedAssetDecimals();
        if (uAssetDecimals >= canonicalAssetDecimals) {
            return amount * 10 ** (uAssetDecimals - canonicalAssetDecimals);
        }
        return amount / 10 ** (canonicalAssetDecimals - uAssetDecimals);
    }

    /// @dev Rescales from uAsset decimals back to canonical asset decimals.
    function _scaleUAssetToCanonicalAsset(uint256 amount, Math.Rounding rounding) internal view returns (uint256) {
        (uint8 canonicalAssetDecimals, uint8 uAssetDecimals) = _cachedAssetDecimals();
        if (canonicalAssetDecimals >= uAssetDecimals) {
            return amount * 10 ** (canonicalAssetDecimals - uAssetDecimals);
        }

        uint256 factor = 10 ** (uAssetDecimals - canonicalAssetDecimals);
        // Ceil rounding: (amount - 1) / factor + 1 ensures rounding up even for amounts not evenly divisible by the factor.
        if (rounding == Math.Rounding.Ceil && amount != 0) {
            return (amount - 1) / factor + 1;
        }
        return amount / factor;
    }

    function _cachedAssetDecimals() internal view returns (uint8 canonicalAssetDecimals, uint8 uAssetDecimals) {
        OutrunStakingPositionStorage storage $ = _getStorage();
        return ($.canonicalAssetDecimals, $.uAssetDecimals);
    }

    function _applyPositionRedeem(
        uint256 positionId,
        Position storage position,
        uint256 syRedeemed,
        uint256 UAssetBurned
    ) internal {
        OutrunStakingPositionStorage storage $ = _getStorage();
        uint256 syStaked = position.syStaked;
        uint256 positionUAssetMinted = position.UAssetMinted;
        uint256 remainingSY;
        uint256 remainingUAsset;

        unchecked {
            // Total staked SY falls by the amount leaving the position.
            $.syTotalStaking -= syRedeemed;
            remainingSY = syStaked - syRedeemed;
            remainingUAsset = positionUAssetMinted - UAssetBurned;
        }

        if (remainingSY == 0) {
            // Full redeem clears the position so the id can no longer be used.
            delete $.positions[positionId];
            return;
        }

        // Partial redeem keeps the same position id with reduced SY and reduced debt.
        position.syStaked = remainingSY;
        position.UAssetMinted = remainingUAsset;
    }

    // slither-disable-next-line timestamp
    function _previewRedeemPositionDebt(uint256 positionId, uint256 syRedeemed)
        internal
        view
        returns (uint256 UAssetBurned)
    {
        Position storage position = _getStorage().positions[positionId];
        uint128 deadline = position.deadline;
        if (block.timestamp < deadline) revert LockTimeNotExpired(deadline);

        uint256 syStaked = position.syStaked;
        uint256 positionUAssetMinted = position.UAssetMinted;
        _validateRedeemAmount(syStaked, syRedeemed);

        UAssetBurned = _computeRedeemPositionDebt(positionUAssetMinted, syRedeemed, syStaked);
    }

    function _validateRedeemAmount(uint256 syStaked, uint256 syRedeemed) internal pure {
        if (syRedeemed == 0) revert ZeroInput();
        if (syRedeemed > syStaked) revert ExceedsPositionBalance(syRedeemed, syStaked);
    }

    /// @dev Partial redeem uses ceil rounding so remaining SY cannot leave orphaned debt on the position.
    /// Full redeem (all SY) burns all remaining debt exactly — no rounding needed.
    function _computeRedeemPositionDebt(uint256 positionUAssetMinted, uint256 syRedeemed, uint256 syStaked)
        internal
        pure
        returns (uint256 UAssetBurned)
    {
        if (syRedeemed == syStaked) return positionUAssetMinted;

        // Partial redeem rounds debt up so remaining SY cannot strand unburned debt on the position.
        UAssetBurned = Math.mulDiv(positionUAssetMinted, syRedeemed, syStaked, Math.Rounding.Ceil);
        if (UAssetBurned >= positionUAssetMinted) revert PartialRedeemMustLeaveDebt();
    }

    function _redeemTokenOut(address _SY, address receiver, address tokenOut, uint256 syRedeemed, uint256 minTokenOut)
        internal
        returns (uint256 amountTokenOut)
    {
        if (tokenOut == _SY) {
            // The receiver asked for SY itself, so transfer the redeemed SY without adapter conversion.
            amountTokenOut = syRedeemed;
            _transferSY(_SY, receiver, syRedeemed);
        } else {
            // Any other tokenOut must be produced by the SY adapter's redeem path.
            amountTokenOut = IStandardizedYield(_SY).redeem(receiver, syRedeemed, tokenOut, minTokenOut, false);
        }
    }

    function _previewTokenOut(address _SY, address tokenOut, uint256 amountInSY)
        internal
        view
        returns (uint256 amountTokenOut)
    {
        if (tokenOut == _SY) {
            // Previewing direct SY output is just the same SY amount.
            amountTokenOut = amountInSY;
        } else {
            // Adapter preview handles non-SY token conversion.
            amountTokenOut = IStandardizedYield(_SY).previewRedeem(tokenOut, amountInSY);
        }
    }

    function _transferSY(address receiver, uint256 syAmount) internal {
        _transferSY(SY(), receiver, syAmount);
    }

    function _transferSY(address _SY, address receiver, uint256 syAmount) internal {
        if (!IERC20(_SY).transfer(receiver, syAmount)) revert SYTransferFailed();
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
