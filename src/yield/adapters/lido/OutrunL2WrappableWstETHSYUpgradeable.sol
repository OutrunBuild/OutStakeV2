// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {SYBaseUpgradeable} from "../../SYBaseUpgradeable.sol";
import {ArrayLib} from "../../../libraries/ArrayLib.sol";
import {IL2StETH} from "../../../integrations/lido/interfaces/IL2StETH.sol";

contract OutrunL2WrappableWstETHSYUpgradeable is SYBaseUpgradeable {
    /// @custom:storage-location erc7201:outrun.storage.OutrunL2WrappableWstETHSY
    // forge-lint: disable-next-line(pascal-case-struct)
    struct OutrunL2WrappableWstETHSYStorage {
        address STETH;
        address underlyingAssetOnEthAddr;
        uint8 underlyingAssetOnEthDecimals;
    }

    // keccak256(abi.encode(uint256(keccak256("outrun.storage.OutrunL2WrappableWstETHSY")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant OUTRUN_L2_WRAPPABLE_WST_ETH_SY_STORAGE_LOCATION =
        0x9da4bc70408d68d126efeec83eb110f8384c649e456fbb92edf8e08a726b7a00;

    function initialize(
        address owner_,
        address stETH_,
        address wstETH_,
        address underlyingAssetOnEthAddr_,
        uint8 underlyingAssetOnEthDecimals_
    ) external initializer {
        if (stETH_ == address(0) || underlyingAssetOnEthAddr_ == address(0)) {
            revert SYZeroAddress();
        }
        __SYBase_init("SY Lido wstETH", "SY wstETH", wstETH_, owner_);
        OutrunL2WrappableWstETHSYStorage storage $ = _getStorage();
        $.STETH = stETH_;
        $.underlyingAssetOnEthAddr = underlyingAssetOnEthAddr_;
        $.underlyingAssetOnEthDecimals = underlyingAssetOnEthDecimals_;
    }

    function _getStorage() private pure returns (OutrunL2WrappableWstETHSYStorage storage $) {
        // slither-disable-next-line assembly
        assembly {
            $.slot := OUTRUN_L2_WRAPPABLE_WST_ETH_SY_STORAGE_LOCATION
        }
    }

    function STETH() public view returns (address) {
        return _getStorage().STETH;
    }

    function _deposit(address tokenIn, uint256 amountDeposited) internal override returns (uint256 amountSharesOut) {
        address _STETH = STETH();
        if (tokenIn == _STETH) amountSharesOut = IL2StETH(_STETH).unwrap(amountDeposited);
        else amountSharesOut = amountDeposited;
    }

    // slither-disable-next-line reentrancy-no-eth
    function _redeem(address receiver, address tokenOut, uint256 amountSharesToRedeem)
        internal
        override
        returns (uint256 amountTokenOut)
    {
        address _STETH = STETH();
        if (tokenOut == _STETH) {
            address _yieldBearingToken = yieldBearingToken();
            _safeApproveInf(_yieldBearingToken, _STETH);
            amountTokenOut = IL2StETH(_STETH).wrap(amountSharesToRedeem);
            _transferOut(_STETH, receiver, amountTokenOut);
        } else {
            amountTokenOut = amountSharesToRedeem;
            _transferOut(yieldBearingToken(), receiver, amountTokenOut);
        }
    }

    function exchangeRate() public view override returns (uint256 res) {
        return IL2StETH(STETH()).getTokensByShares(1 ether);
    }

    function _previewDeposit(address tokenIn, uint256 amountTokenToDeposit) internal view override returns (uint256) {
        address _STETH = STETH();
        if (tokenIn == _STETH) return IL2StETH(_STETH).getSharesByTokens(amountTokenToDeposit);
        return amountTokenToDeposit;
    }

    function _previewRedeem(address tokenOut, uint256 amountSharesToRedeem) internal view override returns (uint256) {
        address _STETH = STETH();
        if (tokenOut == _STETH) return IL2StETH(_STETH).getTokensByShares(amountSharesToRedeem);
        return amountSharesToRedeem;
    }

    function getTokensIn() public view override returns (address[] memory res) {
        return ArrayLib.create(STETH(), yieldBearingToken());
    }

    function getTokensOut() public view override returns (address[] memory res) {
        return ArrayLib.create(STETH(), yieldBearingToken());
    }

    function isValidTokenIn(address token) public view override returns (bool) {
        return token == STETH() || token == yieldBearingToken();
    }

    function isValidTokenOut(address token) public view override returns (bool) {
        return token == STETH() || token == yieldBearingToken();
    }

    function assetInfo() external view returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        OutrunL2WrappableWstETHSYStorage storage $ = _getStorage();
        return (AssetType.TOKEN, $.underlyingAssetOnEthAddr, $.underlyingAssetOnEthDecimals);
    }
}
