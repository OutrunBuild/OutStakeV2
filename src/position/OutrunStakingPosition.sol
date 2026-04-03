// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IOutrunStakeManager} from "./interfaces/IOutrunStakeManager.sol";
import {IStandardizedYield} from "../yield/interfaces/IStandardizedYield.sol";
import {IUniversalAssets} from "../assets/interfaces/IUniversalAssets.sol";
import {SYUtils} from "../libraries/SYUtils.sol";
import {TokenHelper} from "../libraries/TokenHelper.sol";
import {AutoIncrementId} from "../libraries/AutoIncrementId.sol";

/**
 * @title Outrun Staking Position
 * @notice Infrastructure position book for locked stake positions and the public wrap-stake pool.
 */
contract OutrunStakingPosition is IOutrunStakeManager, AutoIncrementId, TokenHelper, Pausable, Ownable {
    address public immutable SY;

    uint256 public minStake;
    uint256 public syTotalStaking;
    uint256 public syWrapStaking;
    uint256 public wrapUAssetDebt;

    address public uAsset;
    address public revenuePool;
    address public keeper;

    mapping(uint256 positionId => Position) public positions;

    constructor(address owner_, uint256 minStake_, address revenuePool_, address sy_, address uAsset_) Ownable(owner_) {
        SY = sy_;
        uAsset = uAsset_;
        minStake = minStake_;
        revenuePool = revenuePool_;
    }

    modifier onlyPositionOwner(uint256 positionId) {
        _onlyPositionOwner(positionId);
        _;
    }

    function _onlyPositionOwner(uint256 positionId) internal view {
        Position storage position = positions[positionId];
        if (position.owner == address(0) || position.owner != msg.sender) revert PositionAccessDenied();
    }

    modifier onlyKeeper() {
        _onlyKeeper();
        _;
    }

    function _onlyKeeper() internal view {
        if (msg.sender != keeper) revert PermissionDenied();
    }

    /**
     * @notice Previews how much uAsset a direct stake would mint.
     * @dev Quote-only helper; does not mutate contract state.
     * @param amountInSY Amount of SY to stake.
     * @return UAssetMintable Amount of uAsset expected to be minted.
     */
    function previewStake(uint256 amountInSY) external view returns (uint256 UAssetMintable) {
        _validateMinStake(amountInSY);
        UAssetMintable = _syToAsset(amountInSY);
    }

    /**
     * @notice Previews how much uAsset a wrap stake would mint.
     * @dev Quote-only helper; does not mutate contract state.
     * @param amountInSY Amount of SY to add to the wrap pool.
     * @return UAssetMintable Amount of uAsset expected to be minted.
     */
    function previewWrapStake(uint256 amountInSY) external view returns (uint256 UAssetMintable) {
        if (amountInSY == 0) revert ZeroInput();
        UAssetMintable = _syToAsset(amountInSY);
    }

    /**
     * @notice Previews additional uAsset drawable from an existing position.
     * @dev Returns only the incremental drawable amount above current minted debt.
     * @param positionId Identifier of the position to inspect.
     * @return UAssetMintable Additional uAsset currently drawable from the position.
     */
    function previewDrawUAsset(uint256 positionId) public view returns (uint256 UAssetMintable) {
        Position storage position = positions[positionId];
        if (position.owner == address(0)) revert PositionAccessDenied();

        uint256 currentValue = _syToAsset(position.syStaked);
        uint256 minted = position.UAssetMinted;
        if (currentValue <= minted) return 0;

        UAssetMintable = currentValue - minted;
    }

    /**
     * @notice Previews a position redemption into SY or another output token.
     * @dev Quote-only helper; does not mutate contract state.
     * @param positionId Identifier of the position being redeemed.
     * @param syRedeemed Amount of SY principal to redeem from the position.
     * @param tokenOut Token requested on redemption.
     * @return UAssetBurned Amount of uAsset expected to be burned.
     * @return amountTokenOut Amount of output token expected to be received.
     */
    function previewRedeem(uint256 positionId, uint256 syRedeemed, address tokenOut)
        public
        view
        returns (uint256 UAssetBurned, uint256 amountTokenOut)
    {
        Position storage position = positions[positionId];
        if (position.owner == address(0)) revert PositionAccessDenied();
        if (syRedeemed == 0) revert ZeroInput();
        if (syRedeemed > position.syStaked) revert ExceedsPositionBalance(syRedeemed, position.syStaked);

        UAssetBurned = Math.mulDiv(position.UAssetMinted, syRedeemed, position.syStaked);
        if (tokenOut == SY) {
            amountTokenOut = syRedeemed;
        } else {
            amountTokenOut = IStandardizedYield(SY).previewRedeem(tokenOut, syRedeemed);
        }
    }

    /**
     * @notice Previews a wrap-pool redemption into SY or another output token.
     * @dev Quote-only helper; does not mutate contract state.
     * @param amountInUAsset Amount of uAsset to redeem.
     * @param tokenOut Token requested on redemption.
     * @return amountTokenOut Amount of output token expected to be received.
     */
    function previewWrapRedeem(uint256 amountInUAsset, address tokenOut) public view returns (uint256 amountTokenOut) {
        if (amountInUAsset == 0) revert ZeroInput();

        uint256 amountInSY = _assetToSy(amountInUAsset);
        if (tokenOut == SY) {
            amountTokenOut = amountInSY;
        } else {
            amountTokenOut = IStandardizedYield(SY).previewRedeem(tokenOut, amountInSY);
        }
    }

    /**
     * @notice Stakes SY into a locked position and mints uAsset to a chosen receiver.
     * @dev Transfers SY in, records `positionOwner` on the position, and mints the matching uAsset debt to `uAssetReceiver`.
     * @param amountInSY Amount of SY to stake.
     * @param lockupDays Number of days the position remains locked.
     * @param positionOwner Address that owns the created position.
     * @param uAssetReceiver Address receiving the initially minted uAsset.
     * @return positionId Identifier of the created position.
     * @return UAssetMinted Amount of uAsset minted for the new position.
     */
    function stake(uint256 amountInSY, uint128 lockupDays, address positionOwner, address uAssetReceiver)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 positionId, uint256 UAssetMinted)
    {
        if (positionOwner == address(0) || uAssetReceiver == address(0)) revert ZeroInput();

        _validateMinStake(amountInSY);
        _transferIn(SY, msg.sender, amountInSY);

        uint256 principalValue = _syToAsset(amountInSY);
        _checkUAssetMintCap(principalValue);

        unchecked {
            syTotalStaking += amountInSY;
        }

        positionId = _nextId();
        UAssetMinted = principalValue;
        positions[positionId] = Position({
            owner: positionOwner,
            syStaked: amountInSY,
            UAssetMinted: UAssetMinted,
            startTime: uint128(block.timestamp),
            deadline: uint128(block.timestamp + lockupDays * 1 days)
        });

        IUniversalAssets(uAsset).mint(uAssetReceiver, UAssetMinted);

        emit Stake(positionId, positionOwner, amountInSY, principalValue, UAssetMinted, positions[positionId].deadline);
    }

    /**
     * @notice Mints newly drawable uAsset from an existing position.
     * @dev Uses the current SY-to-asset conversion to measure incremental draw capacity.
     * @param positionId Identifier of the position to draw against.
     * @param recipient Address receiving the minted uAsset.
     * @return amountInUAsset Amount of uAsset minted to the recipient.
     */
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

        Position storage position = positions[positionId];
        position.UAssetMinted += amountInUAsset;

        _checkUAssetMintCap(amountInUAsset);
        IUniversalAssets(uAsset).mint(recipient, amountInUAsset);

        emit DrawUAsset(positionId, recipient, amountInUAsset);
    }

    /**
     * @notice Adds SY to the wrap pool and mints uAsset to a recipient.
     * @dev This path tracks principal in the shared wrap pool instead of a per-user position.
     * @param amountInSY Amount of SY to add to the wrap pool.
     * @param uAssetRecipient Address receiving the minted uAsset.
     * @return UAssetAmount Amount of uAsset minted.
     */
    function wrapStake(uint256 amountInSY, address uAssetRecipient)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 UAssetAmount)
    {
        if (uAssetRecipient == address(0) || amountInSY == 0) revert ZeroInput();

        _transferIn(SY, msg.sender, amountInSY);

        uint256 principalValue = _syToAsset(amountInSY);
        _checkUAssetMintCap(principalValue);

        unchecked {
            syTotalStaking += amountInSY;
            syWrapStaking += amountInSY;
            wrapUAssetDebt += principalValue;
        }

        UAssetAmount = principalValue;
        IUniversalAssets(uAsset).mint(uAssetRecipient, UAssetAmount);

        emit WrapStake(amountInSY, UAssetAmount, uAssetRecipient);
    }

    /**
     * @notice Redeems part or all of a matured position into SY or another token.
     * @dev Burns the caller's uAsset debt before transferring redemption proceeds.
     * @param positionId Identifier of the position to redeem from.
     * @param syRedeemed Amount of SY principal to redeem.
     * @param receiver Address receiving the redemption proceeds.
     * @param tokenOut Token requested on redemption.
     * @return UAssetBurned Amount of uAsset burned from the caller.
     * @return amountTokenOut Amount of output token delivered to the receiver.
     */
    function redeem(uint256 positionId, uint256 syRedeemed, address receiver, address tokenOut)
        external
        onlyPositionOwner(positionId)
        nonReentrant
        whenNotPaused
        returns (uint256 UAssetBurned, uint256 amountTokenOut)
    {
        if (receiver == address(0)) revert ZeroInput();

        Position storage position = positions[positionId];
        uint128 deadline = position.deadline;
        if (block.timestamp < deadline) revert LockTimeNotExpired(deadline);

        uint256 syStaked = position.syStaked;
        uint256 positionUAssetMinted = position.UAssetMinted;
        if (syRedeemed == 0) revert ZeroInput();
        if (syRedeemed > syStaked) revert ExceedsPositionBalance(syRedeemed, syStaked);

        UAssetBurned = Math.mulDiv(positionUAssetMinted, syRedeemed, syStaked);
        IUniversalAssets(uAsset).repay(msg.sender, UAssetBurned);

        _applyPositionRedeem(positionId, position, syStaked, positionUAssetMinted, syRedeemed, UAssetBurned);

        if (tokenOut == SY) {
            amountTokenOut = syRedeemed;
            _transferSY(receiver, syRedeemed);
        } else {
            amountTokenOut = IStandardizedYield(SY).redeem(receiver, syRedeemed, tokenOut, 0, false);
        }

        emit Redeem(positionId, msg.sender, syRedeemed, UAssetBurned, receiver, tokenOut, amountTokenOut);
    }

    /**
     * @notice Redeems wrap-pool uAsset into SY or another token.
     * @dev Burns wrap-pool debt and reduces shared wrap-pool principal accounting.
     * @param amountInUAsset Amount of uAsset to redeem.
     * @param receiver Address receiving the redemption proceeds.
     * @param tokenOut Token requested on redemption.
     * @return amountTokenOut Amount of output token delivered to the receiver.
     */
    function wrapRedeem(uint256 amountInUAsset, address receiver, address tokenOut)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 amountTokenOut)
    {
        if (receiver == address(0) || amountInUAsset == 0) revert ZeroInput();
        if (amountInUAsset > wrapUAssetDebt) revert ErrorInput();

        uint256 amountInSY = _assetToSy(amountInUAsset);
        if (amountInSY > syWrapStaking) revert ExceedsWrapPoolBalance(amountInSY, syWrapStaking);
        amountTokenOut = previewWrapRedeem(amountInUAsset, tokenOut);

        IUniversalAssets(uAsset).repay(msg.sender, amountInUAsset);

        unchecked {
            syTotalStaking -= amountInSY;
            syWrapStaking -= amountInSY;
            wrapUAssetDebt -= amountInUAsset;
        }

        if (tokenOut == SY) {
            _transferSY(receiver, amountInSY);
        } else {
            amountTokenOut = IStandardizedYield(SY).redeem(receiver, amountInSY, tokenOut, 0, false);
        }

        emit WrapRedeem(receiver, amountInUAsset, amountTokenOut, tokenOut);
    }

    /**
     * @notice Lets the keeper redeem a matured position by burning keeper-provided uAsset.
     * @dev Splits redeemed SY between keeper principal recovery and owner excess value.
     * @param positionId Identifier of the position being redeemed.
     * @param amountInUAsset Amount of uAsset the keeper burns.
     * @param receiver Address receiving the keeper principal in SY.
     * @return UAssetBurned Amount of uAsset burned by the keeper.
     * @return keeperPrincipalSY Amount of SY principal sent to the keeper receiver.
     * @return ownerExcessSY Excess SY sent back to the position owner.
     */
    function keepRedeem(uint256 positionId, uint256 amountInUAsset, address receiver)
        external
        onlyKeeper
        nonReentrant
        whenNotPaused
        returns (uint256 UAssetBurned, uint256 keeperPrincipalSY, uint256 ownerExcessSY)
    {
        if (receiver == address(0)) revert ZeroInput();

        Position storage position = positions[positionId];
        address positionOwner = position.owner;
        if (positionOwner == address(0)) revert PositionAccessDenied();

        uint128 deadline = position.deadline;
        if (block.timestamp < deadline) revert LockTimeNotExpired(deadline);

        uint256 syStaked = position.syStaked;
        uint256 positionUAssetMinted = position.UAssetMinted;
        if (amountInUAsset == 0) revert ZeroInput();
        if (amountInUAsset > positionUAssetMinted) revert ErrorInput();

        UAssetBurned = amountInUAsset;
        IUniversalAssets(uAsset).repay(msg.sender, UAssetBurned);

        keeperPrincipalSY = _assetToSy(UAssetBurned);
        uint256 syRedeemed = Math.mulDiv(syStaked, amountInUAsset, positionUAssetMinted);
        if (keeperPrincipalSY > syRedeemed) keeperPrincipalSY = syRedeemed;
        ownerExcessSY = syRedeemed - keeperPrincipalSY;

        _applyPositionRedeem(positionId, position, syStaked, positionUAssetMinted, syRedeemed, UAssetBurned);

        _transferSY(receiver, keeperPrincipalSY);
        _transferSY(positionOwner, ownerExcessSY);

        emit KeepRedeem(positionId, positionOwner, syRedeemed, UAssetBurned, receiver, keeperPrincipalSY, ownerExcessSY);
    }

    /**
     * @notice Harvests wrap-pool yield above outstanding wrap debt to the revenue pool.
     * @dev Harvestable yield is limited to wrap-pool SY exceeding debt-equivalent SY.
     * @param tokenOut Token requested for harvested yield.
     * @return amountTokenOut Amount of harvested token sent to the revenue pool.
     */
    function harvestWrapYield(address tokenOut)
        external
        onlyOwner
        nonReentrant
        whenNotPaused
        returns (uint256 amountTokenOut)
    {
        uint256 wrapPoolSY = syWrapStaking;
        uint256 wrapDebtInSY = _assetToSy(wrapUAssetDebt);
        if (wrapPoolSY <= wrapDebtInSY) return 0;

        uint256 amountInSY = wrapPoolSY - wrapDebtInSY;
        unchecked {
            syTotalStaking -= amountInSY;
            syWrapStaking -= amountInSY;
        }

        if (tokenOut == SY) {
            _transferSY(revenuePool, amountInSY);
            amountTokenOut = amountInSY;
        } else {
            amountTokenOut = IStandardizedYield(SY).redeem(revenuePool, amountInSY, tokenOut, 0, false);
        }

        emit HarvestWrapYield(revenuePool, tokenOut, amountInSY, amountTokenOut);
    }

    /**
     * @notice Pauses user-facing state-changing entrypoints.
     * @dev Owner-only emergency stop for mutating external functions guarded by `whenNotPaused`.
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpauses user-facing state-changing entrypoints.
     * @dev Owner-only action that restores mutating external functions guarded by `whenNotPaused`.
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Updates the minimum SY stake required for opening a position.
     * @dev Owner-only configuration update.
     * @param minStake_ New minimum stake amount.
     */
    function setMinStake(uint256 minStake_) external onlyOwner {
        minStake = minStake_;
        emit SetMinStake(minStake_);
    }

    /**
     * @notice Updates the uAsset contract used for minting and burning.
     * @dev Owner-only configuration update.
     * @param uAsset_ Address of the new uAsset contract.
     */
    function setUAsset(address uAsset_) external onlyOwner {
        if (uAsset_ == address(0)) revert ZeroInput();
        uAsset = uAsset_;
        emit SetUAsset(uAsset_);
    }

    /**
     * @notice Updates the revenue pool receiving harvested wrap yield.
     * @dev Owner-only configuration update.
     * @param revenuePool_ Address of the new revenue pool.
     */
    function setRevenuePool(address revenuePool_) external onlyOwner {
        if (revenuePool_ == address(0)) revert ZeroInput();
        revenuePool = revenuePool_;
        emit SetRevenuePool(revenuePool_);
    }

    /**
     * @notice Updates the keeper address.
     * @dev Owner-only configuration update.
     * @param keeper_ Address granted keeper permissions.
     */
    function setKeeper(address keeper_) external onlyOwner {
        if (keeper_ == address(0)) revert ZeroInput();
        keeper = keeper_;
        emit SetKeeper(keeper_);
    }

    function _validateMinStake(uint256 amountInSY) internal view {
        if (amountInSY < minStake) revert MinStakeInsufficient(minStake);
    }

    function _checkUAssetMintCap(uint256 amount) internal view {
        if (IUniversalAssets(uAsset).checkMintableAmount(address(this)) < amount) {
            revert UAssetMintingCapReached();
        }
    }

    function _syToAsset(uint256 amountInSY) internal view returns (uint256) {
        return SYUtils.syToAsset(IStandardizedYield(SY).exchangeRate(), amountInSY);
    }

    function _assetToSy(uint256 amountInAsset) internal view returns (uint256) {
        return SYUtils.assetToSy(IStandardizedYield(SY).exchangeRate(), amountInAsset);
    }

    function _applyPositionRedeem(
        uint256 positionId,
        Position storage position,
        uint256 syStaked,
        uint256 positionUAssetMinted,
        uint256 syRedeemed,
        uint256 UAssetBurned
    ) internal {
        uint256 remainingSY;
        uint256 remainingUAsset;

        unchecked {
            syTotalStaking -= syRedeemed;
            remainingSY = syStaked - syRedeemed;
            remainingUAsset = positionUAssetMinted - UAssetBurned;
        }

        if (remainingSY == 0) {
            delete positions[positionId];
            return;
        }

        position.syStaked = remainingSY;
        position.UAssetMinted = remainingUAsset;
    }

    function _transferSY(address receiver, uint256 syAmount) internal {
        if (!IERC20(SY).transfer(receiver, syAmount)) revert SYTransferFailed();
    }
}
