// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {IListaStakeManager} from "../../../integrations/lista/interfaces/IListaStakeManager.sol";
import {ArrayLib} from "../../../libraries/ArrayLib.sol";
import {SYBaseUpgradeable} from "../../SYBaseUpgradeable.sol";

contract OutrunSlisBNBSYUpgradeable is SYBaseUpgradeable {
    /// @custom:storage-location erc7201:outrun.storage.OutrunSlisBNBSY
    // forge-lint: disable-next-line(pascal-case-struct)
    struct OutrunSlisBNBSYStorage {
        address STAKE_MANAGER;
    }

    // keccak256(abi.encode(uint256(keccak256("outrun.storage.OutrunSlisBNBSY")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant OUTRUN_SLIS_BNB_SY_STORAGE_LOCATION =
        0x7eac519ceef6d43eab45b04bb8d5ed66a747bcd5dc85b70bf40db56a58a1eb00;

    error InvalidStakeManager();
    error StakeManagerDepositZero();

    function initialize(address owner_, address slisBNB_, address stakeManager_) external initializer {
        if (slisBNB_ == address(0) || stakeManager_ == address(0)) revert SYZeroAddress();
        if (IListaStakeManager(stakeManager_).convertSnBnbToBnb(1 ether) < 1 ether) revert InvalidStakeManager();
        __SYBase_init("SY Lista slisBNB", "SY slisBNB", slisBNB_, owner_);
        _getStorage().STAKE_MANAGER = stakeManager_;
    }

    function _getStorage() private pure returns (OutrunSlisBNBSYStorage storage $) {
        // slither-disable-next-line assembly
        assembly {
            $.slot := OUTRUN_SLIS_BNB_SY_STORAGE_LOCATION
        }
    }

    function STAKE_MANAGER() public view returns (address) {
        return _getStorage().STAKE_MANAGER;
    }

    // slither-disable-next-line reentrancy-eth,reentrancy-balance
    function _deposit(address tokenIn, uint256 amountDeposited) internal override returns (uint256 amountSharesOut) {
        if (tokenIn == NATIVE) {
            address _yieldBearingToken = yieldBearingToken();
            uint256 beforeBalance = _selfBalance(_yieldBearingToken);
            IListaStakeManager(STAKE_MANAGER()).deposit{value: amountDeposited}();
            uint256 afterBalance = _selfBalance(_yieldBearingToken);
            amountSharesOut = afterBalance - beforeBalance;
            // slither-disable-next-line incorrect-equality
            if (amountSharesOut == 0) revert StakeManagerDepositZero();
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
        return IListaStakeManager(STAKE_MANAGER()).convertSnBnbToBnb(1 ether);
    }

    function _previewDeposit(address tokenIn, uint256 amountTokenToDeposit) internal view override returns (uint256) {
        if (tokenIn == NATIVE) return IListaStakeManager(STAKE_MANAGER()).convertBnbToSnBnb(amountTokenToDeposit);
        return amountTokenToDeposit;
    }

    function _previewRedeem(address, uint256 amountSharesToRedeem) internal pure override returns (uint256) {
        return amountSharesToRedeem;
    }

    function getTokensIn() public view override returns (address[] memory res) {
        return ArrayLib.create(NATIVE, yieldBearingToken());
    }

    function getTokensOut() public view override returns (address[] memory res) {
        return ArrayLib.create(yieldBearingToken());
    }

    function isValidTokenIn(address token) public view override returns (bool) {
        return token == NATIVE || token == yieldBearingToken();
    }

    function isValidTokenOut(address token) public view override returns (bool) {
        return token == yieldBearingToken();
    }

    function assetInfo() external pure returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        return (AssetType.TOKEN, NATIVE, 18);
    }
}
