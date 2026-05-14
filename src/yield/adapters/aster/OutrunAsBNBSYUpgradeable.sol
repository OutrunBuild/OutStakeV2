// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {IAsBnbMinter} from "../../../integrations/aster/interfaces/IAsBnbMinter.sol";
import {IListaBNBStakeManager} from "../../../integrations/aster/interfaces/IListaBNBStakeManager.sol";
import {IYieldProxy} from "../../../integrations/aster/interfaces/IYieldProxy.sol";
import {ArrayLib} from "../../../libraries/ArrayLib.sol";
import {SYBaseUpgradeable} from "../../SYBaseUpgradeable.sol";

contract OutrunAsBNBSYUpgradeable is SYBaseUpgradeable {
    /// @custom:storage-location erc7201:outrun.storage.OutrunAsBNBSY
    // forge-lint: disable-next-line(pascal-case-struct)
    struct OutrunAsBNBSYStorage {
        address AS_BNB_MINTER;
        address SLIS_BNB;
        address YIELD_PROXY;
        address STAKE_MANAGER;
    }

    // keccak256(abi.encode(uint256(keccak256("outrun.storage.OutrunAsBNBSY")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant OUTRUN_AS_BNB_SY_STORAGE_LOCATION =
        0x037ff1f0c947b2628c5e451ad69209eea6dad0b9c31bcbf8186cb85263174300;

    error AsBnbMintQueued();
    error AsBnbMintZeroShares();
    error InvalidAsBnbMinterAsBnb(address expected, address actual);
    error InvalidAsBnbMinterToken(address expected, address actual);
    error InvalidYieldProxy();
    error InvalidStakeManager();

    function initialize(address owner_, address asBNB_, address slisBNB_, address asBnbMinter_) external initializer {
        if (asBNB_ == address(0) || slisBNB_ == address(0) || asBnbMinter_ == address(0)) revert SYZeroAddress();
        (address yieldProxy, address stakeManager) = _validateMinter(asBNB_, slisBNB_, asBnbMinter_);

        __SYBase_init("SY Aster asBNB", "SY asBNB", asBNB_, owner_);
        _storeDependencies(asBnbMinter_, slisBNB_, yieldProxy, stakeManager);
    }

    function _validateMinter(address asBNB_, address slisBNB_, address asBnbMinter_)
        private
        view
        returns (address yieldProxy, address stakeManager)
    {
        address actualAsBnb = IAsBnbMinter(asBnbMinter_).asBnb();
        if (actualAsBnb != asBNB_) revert InvalidAsBnbMinterAsBnb(asBNB_, actualAsBnb);
        address actualToken = IAsBnbMinter(asBnbMinter_).token();
        if (actualToken != slisBNB_) revert InvalidAsBnbMinterToken(slisBNB_, actualToken);
        yieldProxy = IAsBnbMinter(asBnbMinter_).yieldProxy();
        if (yieldProxy == address(0)) revert InvalidYieldProxy();
        stakeManager = IYieldProxy(yieldProxy).stakeManager();
        if (stakeManager == address(0)) revert InvalidStakeManager();
    }

    function _storeDependencies(address asBnbMinter_, address slisBNB_, address yieldProxy, address stakeManager)
        private
    {
        OutrunAsBNBSYStorage storage $ = _getStorage();
        $.AS_BNB_MINTER = asBnbMinter_;
        $.SLIS_BNB = slisBNB_;
        $.YIELD_PROXY = yieldProxy;
        $.STAKE_MANAGER = stakeManager;
    }

    function _getStorage() private pure returns (OutrunAsBNBSYStorage storage $) {
        // slither-disable-next-line assembly
        assembly {
            $.slot := OUTRUN_AS_BNB_SY_STORAGE_LOCATION
        }
    }

    function AS_BNB_MINTER() public view returns (address) {
        return _getStorage().AS_BNB_MINTER;
    }

    function SLIS_BNB() public view returns (address) {
        return _getStorage().SLIS_BNB;
    }

    function YIELD_PROXY() public view returns (address) {
        return _getStorage().YIELD_PROXY;
    }

    function STAKE_MANAGER() public view returns (address) {
        return _getStorage().STAKE_MANAGER;
    }

    // slither-disable-next-line reentrancy-eth,reentrancy-no-eth
    function _deposit(address tokenIn, uint256 amountDeposited) internal override returns (uint256 amountSharesOut) {
        address _minter = AS_BNB_MINTER();
        if (tokenIn == NATIVE) {
            amountSharesOut = IAsBnbMinter(_minter).mintAsBnb{value: amountDeposited}();
            if (amountSharesOut == 0) _revertOnZeroShares();
            return amountSharesOut;
        }
        if (tokenIn == SLIS_BNB()) {
            address _slisBNB = SLIS_BNB();
            _safeApproveInf(_slisBNB, _minter);
            amountSharesOut = IAsBnbMinter(_minter).mintAsBnb(amountDeposited);
            if (amountSharesOut == 0) _revertOnZeroShares();
            return amountSharesOut;
        }
        return amountDeposited;
    }

    function _redeem(address receiver, address tokenOut, uint256 amountSharesToRedeem)
        internal
        override
        returns (uint256 amountTokenOut)
    {
        amountTokenOut = amountSharesToRedeem;
        _transferOut(tokenOut, receiver, amountTokenOut);
    }

    function exchangeRate() public view override returns (uint256 res) {
        uint256 slisBnbPerShare = IAsBnbMinter(AS_BNB_MINTER()).convertToTokens(1 ether);
        return IListaBNBStakeManager(STAKE_MANAGER()).convertSnBnbToBnb(slisBnbPerShare);
    }

    function _previewDeposit(address tokenIn, uint256 amountTokenToDeposit) internal view override returns (uint256) {
        address _minter = AS_BNB_MINTER();
        if (tokenIn == NATIVE) {
            uint256 slisBnbAmount = IListaBNBStakeManager(STAKE_MANAGER()).convertBnbToSnBnb(amountTokenToDeposit);
            return IAsBnbMinter(_minter).convertToAsBnb(slisBnbAmount);
        }
        if (tokenIn == SLIS_BNB()) return IAsBnbMinter(_minter).convertToAsBnb(amountTokenToDeposit);
        return amountTokenToDeposit;
    }

    function _previewRedeem(address, uint256 amountSharesToRedeem) internal pure override returns (uint256) {
        return amountSharesToRedeem;
    }

    function getTokensIn() public view override returns (address[] memory res) {
        return ArrayLib.create(NATIVE, SLIS_BNB(), yieldBearingToken());
    }

    function getTokensOut() public view override returns (address[] memory res) {
        return ArrayLib.create(yieldBearingToken());
    }

    function isValidTokenIn(address token) public view override returns (bool) {
        return token == NATIVE || token == SLIS_BNB() || token == yieldBearingToken();
    }

    function isValidTokenOut(address token) public view override returns (bool) {
        return token == yieldBearingToken();
    }

    function assetInfo() external pure returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        return (AssetType.TOKEN, NATIVE, 18);
    }

    function _revertOnZeroShares() private view {
        if (IYieldProxy(YIELD_PROXY()).activitiesOnGoing()) revert AsBnbMintQueued();
        revert AsBnbMintZeroShares();
    }
}
