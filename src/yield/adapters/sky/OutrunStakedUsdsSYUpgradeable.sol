// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {SYBaseUpgradeable} from "../../SYBaseUpgradeable.sol";
import {ArrayLib} from "../../../libraries/ArrayLib.sol";

contract OutrunStakedUsdsSYUpgradeable is SYBaseUpgradeable {
    /// @custom:storage-location erc7201:outrun.storage.OutrunStakedUsdsSY
    // forge-lint: disable-next-line(pascal-case-struct)
    struct OutrunStakedUsdsSYStorage {
        address USDS;
    }

    // keccak256(abi.encode(uint256(keccak256("outrun.storage.OutrunStakedUsdsSY")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant OUTRUN_STAKED_USDS_SY_STORAGE_LOCATION =
        0x74aedace728c226c8b576fb3084503c20ae3f009148ad8baca9527cdb56df900;

    function initialize(address owner_, address USDS_, address sUSDS_) external initializer {
        if (USDS_ == address(0)) revert SYZeroAddress();
        __SYBase_init("SY Sky sUSDS", "SY sUSDS", sUSDS_, owner_);
        _getStorage().USDS = USDS_;
    }

    function _getStorage() private pure returns (OutrunStakedUsdsSYStorage storage $) {
        // slither-disable-next-line assembly
        assembly {
            $.slot := OUTRUN_STAKED_USDS_SY_STORAGE_LOCATION
        }
    }

    function USDS() public view returns (address) {
        return _getStorage().USDS;
    }

    function _deposit(address tokenIn, uint256 amountDeposited) internal override returns (uint256 amountSharesOut) {
        address _USDS = USDS();
        address _yieldBearingToken = yieldBearingToken();
        if (tokenIn == _USDS) {
            _safeApproveInf(_USDS, _yieldBearingToken);
            amountSharesOut = IERC4626(_yieldBearingToken).deposit(amountDeposited, address(this));
        } else {
            amountSharesOut = amountDeposited;
        }
    }

    function _redeem(address receiver, address tokenOut, uint256 amountSharesToRedeem)
        internal
        override
        returns (uint256 amountTokenOut)
    {
        address _yieldBearingToken = yieldBearingToken();
        if (tokenOut == USDS()) {
            amountTokenOut = IERC4626(_yieldBearingToken).redeem(amountSharesToRedeem, receiver, address(this));
        } else {
            _transferOut(_yieldBearingToken, receiver, amountSharesToRedeem);
            amountTokenOut = amountSharesToRedeem;
        }
    }

    function exchangeRate() public view override returns (uint256 res) {
        return IERC4626(yieldBearingToken()).convertToAssets(1 ether);
    }

    function _previewDeposit(address tokenIn, uint256 amountTokenToDeposit) internal view override returns (uint256) {
        if (tokenIn == USDS()) return IERC4626(yieldBearingToken()).previewDeposit(amountTokenToDeposit);
        return amountTokenToDeposit;
    }

    function _previewRedeem(address tokenOut, uint256 amountSharesToRedeem) internal view override returns (uint256) {
        if (tokenOut == USDS()) return IERC4626(yieldBearingToken()).previewRedeem(amountSharesToRedeem);
        return amountSharesToRedeem;
    }

    function getTokensIn() public view override returns (address[] memory res) {
        return ArrayLib.create(yieldBearingToken(), USDS());
    }

    function getTokensOut() public view override returns (address[] memory res) {
        return ArrayLib.create(yieldBearingToken(), USDS());
    }

    function isValidTokenIn(address token) public view override returns (bool) {
        return token == yieldBearingToken() || token == USDS();
    }

    function isValidTokenOut(address token) public view override returns (bool) {
        return token == yieldBearingToken() || token == USDS();
    }

    function assetInfo() external view returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        return (AssetType.TOKEN, USDS(), 18);
    }
}
