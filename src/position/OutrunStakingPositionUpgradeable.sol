// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IOutrunStakeManager} from "./interfaces/IOutrunStakeManager.sol";
import {IStandardizedYield} from "../yield/interfaces/IStandardizedYield.sol";
import {IUniversalAssets} from "../assets/interfaces/IUniversalAssets.sol";
import {SYUtils} from "../libraries/SYUtils.sol";
import {TokenHelper} from "../libraries/TokenHelper.sol";
import {AutoIncrementIdUpgradeable} from "../libraries/AutoIncrementIdUpgradeable.sol";

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
    }

    // keccak256(abi.encode(uint256(keccak256("outrun.storage.OutrunStakingPosition")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant OUTRUN_STAKING_POSITION_STORAGE_LOCATION =
        0xd6ebf98633cd133425e2ec4f5c3d5a1e15a1a3a82505bb0f6ed101932bed5200;

    constructor() {
        _disableInitializers();
    }

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
        $.SY = sy_;
        $.uAsset = uAsset_;
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

    modifier onlyPositionOwner(uint256 positionId) {
        _onlyPositionOwner(positionId);
        _;
    }

    modifier onlyKeeper() {
        _onlyKeeper();
        _;
    }

    function _onlyKeeper() internal view {
        if (msg.sender != keeper()) revert PermissionDenied();
    }

    function SY() public view returns (address) {
        return _getStorage().SY;
    }

    function minStake() public view returns (uint256) {
        return _getStorage().minStake;
    }

    function syTotalStaking() public view returns (uint256) {
        return _getStorage().syTotalStaking;
    }

    function syWrapStaking() public view returns (uint256) {
        return _getStorage().syWrapStaking;
    }

    function wrapUAssetDebt() public view returns (uint256) {
        return _getStorage().wrapUAssetDebt;
    }

    function uAsset() public view returns (address) {
        return _getStorage().uAsset;
    }

    function revenuePool() public view returns (address) {
        return _getStorage().revenuePool;
    }

    function keeper() public view returns (address) {
        return _getStorage().keeper;
    }

    function positions(uint256 positionId)
        public
        view
        returns (address owner, uint256 syStaked, uint256 UAssetMinted, uint128 startTime, uint128 deadline)
    {
        Position storage position = _getStorage().positions[positionId];
        return (position.owner, position.syStaked, position.UAssetMinted, position.startTime, position.deadline);
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
        Position storage position = _getStorage().positions[positionId];
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
        Position storage position = _getStorage().positions[positionId];
        if (position.owner == address(0)) revert PositionAccessDenied();
        if (syRedeemed == 0) revert ZeroInput();
        if (syRedeemed > position.syStaked) revert ExceedsPositionBalance(syRedeemed, position.syStaked);

        UAssetBurned = Math.mulDiv(position.UAssetMinted, syRedeemed, position.syStaked);
        address _SY = SY();
        if (tokenOut == _SY) amountTokenOut = syRedeemed;
        else amountTokenOut = IStandardizedYield(_SY).previewRedeem(tokenOut, syRedeemed);
    }

    function previewWrapRedeem(uint256 amountInUAsset, address tokenOut) public view returns (uint256 amountTokenOut) {
        if (amountInUAsset == 0) revert ZeroInput();
        uint256 amountInSY = _assetToSy(amountInUAsset);
        address _SY = SY();
        if (tokenOut == _SY) amountTokenOut = amountInSY;
        else amountTokenOut = IStandardizedYield(_SY).previewRedeem(tokenOut, amountInSY);
    }

    function stake(uint256 amountInSY, uint128 lockupDays, address positionOwner, address uAssetReceiver)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 positionId, uint256 UAssetMinted)
    {
        if (positionOwner == address(0) || uAssetReceiver == address(0)) revert ZeroInput();
        address _SY = SY();
        address _uAsset = uAsset();
        _validateMinStake(amountInSY);
        _transferIn(_SY, msg.sender, amountInSY);

        uint256 principalValue = _syToAsset(amountInSY);
        _checkUAssetMintCap(principalValue);

        OutrunStakingPositionStorage storage $ = _getStorage();
        unchecked {
            $.syTotalStaking += amountInSY;
        }

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

        IUniversalAssets(_uAsset).mint(uAssetReceiver, UAssetMinted);
        emit Stake(
            positionId, positionOwner, amountInSY, principalValue, UAssetMinted, $.positions[positionId].deadline
        );
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

        Position storage position = _getStorage().positions[positionId];
        position.UAssetMinted += amountInUAsset;

        address _uAsset = uAsset();
        _checkUAssetMintCap(amountInUAsset);
        IUniversalAssets(_uAsset).mint(recipient, amountInUAsset);
        emit DrawUAsset(positionId, recipient, amountInUAsset);
    }

    function wrapStake(uint256 amountInSY, address uAssetRecipient)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 UAssetAmount)
    {
        if (uAssetRecipient == address(0) || amountInSY == 0) revert ZeroInput();
        address _SY = SY();
        address _uAsset = uAsset();
        _transferIn(_SY, msg.sender, amountInSY);

        uint256 principalValue = _syToAsset(amountInSY);
        _checkUAssetMintCap(principalValue);

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
    function redeem(uint256 positionId, uint256 syRedeemed, address receiver, address tokenOut, uint256 minTokenOut)
        external
        onlyPositionOwner(positionId)
        nonReentrant
        whenNotPaused
        returns (uint256 UAssetBurned, uint256 amountTokenOut)
    {
        if (receiver == address(0)) revert ZeroInput();
        address _SY = SY();
        address _uAsset = uAsset();
        Position storage position = _getStorage().positions[positionId];
        uint128 deadline = position.deadline;
        if (block.timestamp < deadline) revert LockTimeNotExpired(deadline);

        uint256 syStaked = position.syStaked;
        uint256 positionUAssetMinted = position.UAssetMinted;
        if (syRedeemed == 0) revert ZeroInput();
        if (syRedeemed > syStaked) revert ExceedsPositionBalance(syRedeemed, syStaked);
        if (tokenOut == _SY && syRedeemed < minTokenOut) revert InsufficientTokenOut(syRedeemed, minTokenOut);

        UAssetBurned = Math.mulDiv(positionUAssetMinted, syRedeemed, syStaked);
        IUniversalAssets(_uAsset).repay(msg.sender, UAssetBurned);
        _applyPositionRedeem(positionId, position, syRedeemed, UAssetBurned);

        if (tokenOut == _SY) {
            amountTokenOut = syRedeemed;
            _transferSY(receiver, syRedeemed);
        } else {
            amountTokenOut = IStandardizedYield(_SY).redeem(receiver, syRedeemed, tokenOut, minTokenOut, false);
        }

        emit Redeem(positionId, msg.sender, syRedeemed, UAssetBurned, receiver, tokenOut, amountTokenOut);
    }

    // slither-disable-next-line reentrancy-no-eth
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
        uint256 amountInSY = _assetToSy(amountInUAsset);
        if (amountInSY > $.syWrapStaking) revert ExceedsWrapPoolBalance(amountInSY, $.syWrapStaking);

        IUniversalAssets(_uAsset).repay(msg.sender, amountInUAsset);

        unchecked {
            $.syTotalStaking -= amountInSY;
            $.syWrapStaking -= amountInSY;
            $.wrapUAssetDebt -= amountInUAsset;
        }

        if (tokenOut == _SY) {
            if (amountInSY < minTokenOut) revert InsufficientTokenOut(amountInSY, minTokenOut);
            amountTokenOut = amountInSY;
            _transferSY(receiver, amountInSY);
        } else {
            amountTokenOut = IStandardizedYield(_SY).redeem(receiver, amountInSY, tokenOut, minTokenOut, false);
        }

        emit WrapRedeem(receiver, amountInUAsset, amountTokenOut, tokenOut);
    }

    // slither-disable-next-line reentrancy-no-eth,timestamp
    function keepRedeem(uint256 positionId, uint256 amountInUAsset, address receiver)
        external
        onlyKeeper
        nonReentrant
        whenNotPaused
        returns (uint256 UAssetBurned, uint256 keeperPrincipalSY, uint256 ownerExcessSY)
    {
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

        UAssetBurned = amountInUAsset;
        IUniversalAssets(_uAsset).repay(msg.sender, UAssetBurned);

        keeperPrincipalSY = _assetToSy(UAssetBurned);
        uint256 syRedeemed = Math.mulDiv(syStaked, amountInUAsset, positionUAssetMinted);
        if (keeperPrincipalSY > syRedeemed) keeperPrincipalSY = syRedeemed;
        ownerExcessSY = syRedeemed - keeperPrincipalSY;

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
        uint256 wrapDebtInSY = _assetToSy($.wrapUAssetDebt);
        if (wrapPoolSY <= wrapDebtInSY) return 0;

        uint256 amountInSY = wrapPoolSY - wrapDebtInSY;
        address _SY = SY();
        unchecked {
            $.syTotalStaking -= amountInSY;
            $.syWrapStaking -= amountInSY;
        }

        if (tokenOut == _SY) {
            if (amountInSY < minTokenOut) revert InsufficientTokenOut(amountInSY, minTokenOut);
            amountTokenOut = amountInSY;
            _transferSY($.revenuePool, amountInSY);
        } else {
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

    function _onlyPositionOwner(uint256 positionId) internal view {
        Position storage position = _getStorage().positions[positionId];
        if (position.owner == address(0) || position.owner != msg.sender) revert PositionAccessDenied();
    }

    function _validateMinStake(uint256 amountInSY) internal view {
        uint256 minStake_ = minStake();
        if (amountInSY < minStake_) revert MinStakeInsufficient(minStake_);
    }

    function _checkUAssetMintCap(uint256 amount) internal view {
        if (IUniversalAssets(uAsset()).checkMintableAmount(address(this)) < amount) {
            revert UAssetMintingCapReached();
        }
    }

    function _syToAsset(uint256 amountInSY) internal view returns (uint256) {
        return SYUtils.syToAsset(IStandardizedYield(SY()).exchangeRate(), amountInSY);
    }

    function _assetToSy(uint256 amountInAsset) internal view returns (uint256) {
        return SYUtils.assetToSy(IStandardizedYield(SY()).exchangeRate(), amountInAsset);
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
            $.syTotalStaking -= syRedeemed;
            remainingSY = syStaked - syRedeemed;
            remainingUAsset = positionUAssetMinted - UAssetBurned;
        }

        if (remainingSY == 0) {
            delete $.positions[positionId];
            return;
        }

        position.syStaked = remainingSY;
        position.UAssetMinted = remainingUAsset;
    }

    function _transferSY(address receiver, uint256 syAmount) internal {
        if (!IERC20(SY()).transfer(receiver, syAmount)) revert SYTransferFailed();
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
