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
        _validateRedeemAmount(position.syStaked, syRedeemed);

        // Partial redeem debt uses ceil so redeemed SY cannot leave rounded debt dust on the remaining position.
        UAssetBurned = _computeRedeemPositionDebt(position.UAssetMinted, syRedeemed, position.syStaked);
        amountTokenOut = _previewTokenOut(SY(), tokenOut, syRedeemed);
    }

    function previewWrapRedeem(uint256 amountInUAsset, address tokenOut) public view returns (uint256 amountTokenOut) {
        if (amountInUAsset == 0) revert ZeroInput();
        uint256 amountInSY = _assetToSy(amountInUAsset);
        amountTokenOut = _previewTokenOut(SY(), tokenOut, amountInSY);
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
        _checkUAssetMintCap(_uAsset, principalValue);

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
        _checkUAssetMintCap(_uAsset, amountInUAsset);
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
    function redeem(uint256 positionId, uint256 syRedeemed, address receiver, address tokenOut, uint256 minTokenOut)
        external
        onlyPositionOwner(positionId)
        nonReentrant
        whenNotPaused
        returns (uint256 UAssetBurned, uint256 amountTokenOut)
    {
        if (receiver == address(0)) revert ZeroInput();
        address _SY = SY();
        UAssetBurned = _previewRedeemPositionDebt(positionId, syRedeemed);
        _checkDirectSYMinTokenOut(_SY, tokenOut, syRedeemed, minTokenOut);
        _applyRedeemPositionDebt(positionId, syRedeemed, UAssetBurned);
        amountTokenOut = _redeemTokenOut(_SY, receiver, tokenOut, syRedeemed, minTokenOut);

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
        // Floor here so wrap redeem never releases more SY than the repaid wrap debt slice accounts for.
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

        // Floor debt->SY, then clamp, so keeper principal never exceeds the redeemed debt slice in SY.
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
        // Ceil here so harvest leaves enough SY in the wrap pool to keep all remaining debt covered.
        uint256 wrapDebtInSY = _assetToSyUp($.wrapUAssetDebt);
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

    function _checkUAssetMintCap(address _uAsset, uint256 amount) internal view {
        if (IUniversalAssets(_uAsset).checkMintableAmount(address(this)) < amount) {
            revert UAssetMintingCapReached();
        }
    }

    // `canonicalAssetValue` follows `SY.assetInfo().assetDecimals`.
    // `uAssetDebtUnits` follows `uAsset.decimals()`.
    // These helpers first convert via `SY.exchangeRate()` and then rescale across the two decimal domains.
    function _syToAsset(uint256 amountInSY) internal view returns (uint256) {
        address _SY = SY();
        uint256 canonicalAssetValue = SYUtils.syToAsset(IStandardizedYield(_SY).exchangeRate(), amountInSY);
        return _scaleCanonicalAssetToUAsset(canonicalAssetValue);
    }

    function _assetToSy(uint256 amountInAsset) internal view returns (uint256) {
        address _SY = SY();
        uint256 canonicalAssetValue = _scaleUAssetToCanonicalAsset(amountInAsset, Math.Rounding.Floor);
        return SYUtils.assetToSy(IStandardizedYield(_SY).exchangeRate(), canonicalAssetValue);
    }

    function _assetToSyUp(uint256 amountInAsset) internal view returns (uint256) {
        address _SY = SY();
        uint256 canonicalAssetValue = _scaleUAssetToCanonicalAsset(amountInAsset, Math.Rounding.Ceil);
        return SYUtils.assetToSyUp(IStandardizedYield(_SY).exchangeRate(), canonicalAssetValue);
    }

    function _scaleCanonicalAssetToUAsset(uint256 amount) internal view returns (uint256) {
        (uint8 canonicalAssetDecimals, uint8 uAssetDecimals) = _cachedAssetDecimals();
        if (uAssetDecimals >= canonicalAssetDecimals) {
            return amount * 10 ** (uAssetDecimals - canonicalAssetDecimals);
        }
        return amount / 10 ** (canonicalAssetDecimals - uAssetDecimals);
    }

    function _scaleUAssetToCanonicalAsset(uint256 amount, Math.Rounding rounding) internal view returns (uint256) {
        (uint8 canonicalAssetDecimals, uint8 uAssetDecimals) = _cachedAssetDecimals();
        if (canonicalAssetDecimals >= uAssetDecimals) {
            return amount * 10 ** (canonicalAssetDecimals - uAssetDecimals);
        }

        uint256 factor = 10 ** (uAssetDecimals - canonicalAssetDecimals);
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

    // slither-disable-next-line reentrancy-no-eth
    function _applyRedeemPositionDebt(uint256 positionId, uint256 syRedeemed, uint256 UAssetBurned) internal {
        Position storage position = _getStorage().positions[positionId];
        IUniversalAssets(uAsset()).repay(msg.sender, UAssetBurned);
        _applyPositionRedeem(positionId, position, syRedeemed, UAssetBurned);
    }

    function _validateRedeemAmount(uint256 syStaked, uint256 syRedeemed) internal pure {
        if (syRedeemed == 0) revert ZeroInput();
        if (syRedeemed > syStaked) revert ExceedsPositionBalance(syRedeemed, syStaked);
    }

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
            amountTokenOut = syRedeemed;
            _transferSY(_SY, receiver, syRedeemed);
        } else {
            amountTokenOut = IStandardizedYield(_SY).redeem(receiver, syRedeemed, tokenOut, minTokenOut, false);
        }
    }

    function _previewTokenOut(address _SY, address tokenOut, uint256 amountInSY)
        internal
        view
        returns (uint256 amountTokenOut)
    {
        if (tokenOut == _SY) {
            amountTokenOut = amountInSY;
        } else {
            amountTokenOut = IStandardizedYield(_SY).previewRedeem(tokenOut, amountInSY);
        }
    }

    function _checkDirectSYMinTokenOut(address _SY, address tokenOut, uint256 syRedeemed, uint256 minTokenOut)
        internal
        pure
    {
        if (tokenOut == _SY && syRedeemed < minTokenOut) revert InsufficientTokenOut(syRedeemed, minTokenOut);
    }

    function _transferSY(address receiver, uint256 syAmount) internal {
        _transferSY(SY(), receiver, syAmount);
    }

    function _transferSY(address _SY, address receiver, uint256 syAmount) internal {
        if (!IERC20(_SY).transfer(receiver, syAmount)) revert SYTransferFailed();
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
