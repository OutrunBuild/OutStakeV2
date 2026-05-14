// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {SYBaseUpgradeable} from "../../SYBaseUpgradeable.sol";
import {ArrayLib} from "../../../libraries/ArrayLib.sol";

contract OutrunStakedUSDeSYUpgradeable is SYBaseUpgradeable {
    /// @custom:storage-location erc7201:outrun.storage.OutrunStakedUSDeSY
    // forge-lint: disable-next-line(pascal-case-struct)
    struct OutrunStakedUSDeSYStorage {
        address USDE;
    }

    // keccak256(abi.encode(uint256(keccak256("outrun.storage.OutrunStakedUSDeSY")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant OUTRUN_STAKED_USDE_SY_STORAGE_LOCATION =
        0xc6349914f41ee852ec6671cc14b058a0b3e3b25674e5c52708e581f58824ce00;

    function initialize(address owner_, address USDe_, address sUSDe_) external initializer {
        if (USDe_ == address(0)) revert SYZeroAddress();
        __SYBase_init("SY Ethena sUSDe", "SY sUSDe", sUSDe_, owner_);
        _getStorage().USDE = USDe_;
    }

    function _getStorage() private pure returns (OutrunStakedUSDeSYStorage storage $) {
        // slither-disable-next-line assembly
        assembly {
            $.slot := OUTRUN_STAKED_USDE_SY_STORAGE_LOCATION
        }
    }

    function USDE() public view returns (address) {
        return _getStorage().USDE;
    }

    function _deposit(address tokenIn, uint256 amountDeposited) internal override returns (uint256 amountSharesOut) {
        address _USDE = USDE();
        address _yieldBearingToken = yieldBearingToken();
        if (tokenIn == _USDE) {
            _safeApproveInf(_USDE, _yieldBearingToken);
            amountSharesOut = IERC4626(_yieldBearingToken).deposit(amountDeposited, address(this));
        } else {
            amountSharesOut = amountDeposited;
        }
    }

    function _redeem(address receiver, address, uint256 amountSharesToRedeem) internal override returns (uint256) {
        _transferOut(yieldBearingToken(), receiver, amountSharesToRedeem);
        return amountSharesToRedeem;
    }

    function exchangeRate() public view override returns (uint256 res) {
        return IERC4626(yieldBearingToken()).convertToAssets(1 ether);
    }

    function _previewDeposit(address tokenIn, uint256 amountTokenToDeposit) internal view override returns (uint256) {
        if (tokenIn == USDE()) return IERC4626(yieldBearingToken()).previewDeposit(amountTokenToDeposit);
        return amountTokenToDeposit;
    }

    function _previewRedeem(address, uint256 amountSharesToRedeem) internal pure override returns (uint256) {
        return amountSharesToRedeem;
    }

    function getTokensIn() public view override returns (address[] memory res) {
        return ArrayLib.create(yieldBearingToken(), USDE());
    }

    function getTokensOut() public view override returns (address[] memory res) {
        return ArrayLib.create(yieldBearingToken());
    }

    function isValidTokenIn(address token) public view override returns (bool) {
        return token == yieldBearingToken() || token == USDE();
    }

    function isValidTokenOut(address token) public view override returns (bool) {
        return token == yieldBearingToken();
    }

    function assetInfo() external view returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        return (AssetType.TOKEN, USDE(), 18);
    }
}
