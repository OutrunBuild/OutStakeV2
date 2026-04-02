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

    function previewStake(uint256 amountInSY) external view returns (uint256 UAssetMintable) {
        _validateMinStake(amountInSY);
        UAssetMintable = _syToAsset(amountInSY);
    }

    function previewWrapStake(uint256 amountInSY) external view returns (uint256 UAssetMintable) {
        if (amountInSY == 0) revert ZeroInput();
        UAssetMintable = _syToAsset(amountInSY);
    }

    function previewDrawUAsset(uint256 positionId) public view returns (uint256 UAssetMintable) {
        Position storage position = positions[positionId];
        if (position.owner == address(0)) revert PositionAccessDenied();

        uint256 currentValue = _syToAsset(position.syStaked);
        uint256 minted = position.UAssetMinted;
        if (currentValue <= minted) return 0;

        UAssetMintable = currentValue - minted;
    }

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

    function previewWrapRedeem(uint256 amountInUAsset, address tokenOut) public view returns (uint256 amountTokenOut) {
        if (amountInUAsset == 0) revert ZeroInput();

        uint256 amountInSY = _assetToSy(amountInUAsset);
        if (tokenOut == SY) {
            amountTokenOut = amountInSY;
        } else {
            amountTokenOut = IStandardizedYield(SY).previewRedeem(tokenOut, amountInSY);
        }
    }

    function stake(uint256 amountInSY, uint128 lockupDays, address owner_)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 positionId, uint256 UAssetMinted)
    {
        if (owner_ == address(0)) revert ZeroInput();

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
            owner: owner_,
            syStaked: amountInSY,
            UAssetMinted: UAssetMinted,
            startTime: uint128(block.timestamp),
            deadline: uint128(block.timestamp + lockupDays * 1 days)
        });

        IUniversalAssets(uAsset).mint(owner_, UAssetMinted);

        emit Stake(positionId, owner_, amountInSY, principalValue, UAssetMinted, positions[positionId].deadline);
    }

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
        IUniversalAssets(uAsset).burn(msg.sender, UAssetBurned);

        _applyPositionRedeem(positionId, position, syStaked, positionUAssetMinted, syRedeemed, UAssetBurned);

        if (tokenOut == SY) {
            amountTokenOut = syRedeemed;
            _transferSY(receiver, syRedeemed);
        } else {
            amountTokenOut = IStandardizedYield(SY).redeem(receiver, syRedeemed, tokenOut, 0, false);
        }

        emit Redeem(positionId, msg.sender, syRedeemed, UAssetBurned, receiver, tokenOut, amountTokenOut);
    }

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

        IUniversalAssets(uAsset).burn(msg.sender, amountInUAsset);

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
        IUniversalAssets(uAsset).burn(msg.sender, UAssetBurned);

        keeperPrincipalSY = _assetToSy(UAssetBurned);
        uint256 syRedeemed = Math.mulDiv(syStaked, amountInUAsset, positionUAssetMinted);
        if (keeperPrincipalSY > syRedeemed) keeperPrincipalSY = syRedeemed;
        ownerExcessSY = syRedeemed - keeperPrincipalSY;

        _applyPositionRedeem(positionId, position, syStaked, positionUAssetMinted, syRedeemed, UAssetBurned);

        _transferSY(receiver, keeperPrincipalSY);
        _transferSY(positionOwner, ownerExcessSY);

        emit KeepRedeem(positionId, positionOwner, syRedeemed, UAssetBurned, receiver, keeperPrincipalSY, ownerExcessSY);
    }

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

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setMinStake(uint256 minStake_) external onlyOwner {
        minStake = minStake_;
        emit SetMinStake(minStake_);
    }

    function setUAsset(address uAsset_) external onlyOwner {
        if (uAsset_ == address(0)) revert ZeroInput();
        uAsset = uAsset_;
        emit SetUAsset(uAsset_);
    }

    function setRevenuePool(address revenuePool_) external onlyOwner {
        if (revenuePool_ == address(0)) revert ZeroInput();
        revenuePool = revenuePool_;
        emit SetRevenuePool(revenuePool_);
    }

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
