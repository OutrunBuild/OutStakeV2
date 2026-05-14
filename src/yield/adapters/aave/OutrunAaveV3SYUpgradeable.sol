// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {IAToken} from "../../../integrations/aave/interfaces/IAToken.sol";
import {IAaveV3Pool} from "../../../integrations/aave/interfaces/IAaveV3Pool.sol";
import {ArrayLib} from "../../../libraries/ArrayLib.sol";
import {AaveAdapterLib} from "../../../libraries/AaveAdapterLib.sol";
import {SYBaseUpgradeable} from "../../SYBaseUpgradeable.sol";

contract OutrunAaveV3SYUpgradeable is SYBaseUpgradeable {
    /// @custom:storage-location erc7201:outrun.storage.OutrunAaveV3SY
    // forge-lint: disable-next-line(pascal-case-struct)
    struct OutrunAaveV3SYStorage {
        address underlying;
        address aavePool;
    }

    // keccak256(abi.encode(uint256(keccak256("outrun.storage.OutrunAaveV3SY")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant OUTRUN_AAVE_V3_SY_STORAGE_LOCATION =
        0x72217a3ea688bfbd31b48bb32b412c4301717e3e5d9754c566b8b7af0c910a00;
    error AaveZeroShares();

    function initialize(
        string calldata name_,
        string calldata symbol_,
        address aToken_,
        address aavePool_,
        address owner_
    ) external initializer {
        if (aavePool_ == address(0)) revert SYZeroAddress();
        __SYBase_init(name_, symbol_, aToken_, owner_);
        OutrunAaveV3SYStorage storage $ = _getStorage();
        $.underlying = IAToken(aToken_).UNDERLYING_ASSET_ADDRESS();
        $.aavePool = aavePool_;
    }

    function _getStorage() private pure returns (OutrunAaveV3SYStorage storage $) {
        // slither-disable-next-line assembly
        assembly {
            $.slot := OUTRUN_AAVE_V3_SY_STORAGE_LOCATION
        }
    }

    function underlying() public view returns (address) {
        return _getStorage().underlying;
    }

    function aavePool() public view returns (address) {
        return _getStorage().aavePool;
    }

    // slither-disable-next-line reentrancy-no-eth
    function _deposit(address tokenIn, uint256 amountDeposited) internal override returns (uint256 amountSharesOut) {
        address _underlying = underlying();
        address _pool = aavePool();
        if (tokenIn == _underlying) {
            IAToken aToken = IAToken(yieldBearingToken());
            uint256 scaledBefore = aToken.scaledBalanceOf(address(this));
            _safeApproveInf(_underlying, _pool);
            IAaveV3Pool(_pool).supply(_underlying, amountDeposited, address(this), 0);
            amountSharesOut = aToken.scaledBalanceOf(address(this)) - scaledBefore;
        } else {
            amountSharesOut = AaveAdapterLib.calcSharesFromAssetUp(amountDeposited, _getNormalizedIncome());
        }
        if (amountSharesOut == 0) revert AaveZeroShares();
    }

    function _redeem(address receiver, address tokenOut, uint256 amountSharesToRedeem)
        internal
        override
        returns (uint256 amountTokenOut)
    {
        amountTokenOut = AaveAdapterLib.calcSharesToAssetDown(amountSharesToRedeem, _getNormalizedIncome());
        address _underlying = underlying();
        if (tokenOut == _underlying) {
            address _pool = aavePool();
            amountTokenOut = IAaveV3Pool(_pool).withdraw(_underlying, amountTokenOut, receiver);
        } else {
            _transferOut(yieldBearingToken(), receiver, amountTokenOut);
        }
    }

    function exchangeRate() public view override returns (uint256) {
        return _getNormalizedIncome() / 1e9;
    }

    function _previewDeposit(address, uint256 amountTokenToDeposit) internal view override returns (uint256) {
        return AaveAdapterLib.calcSharesFromAssetUp(amountTokenToDeposit, _getNormalizedIncome());
    }

    function _previewRedeem(address, uint256 amountSharesToRedeem) internal view override returns (uint256) {
        return AaveAdapterLib.calcSharesToAssetDown(amountSharesToRedeem, _getNormalizedIncome());
    }

    function _getNormalizedIncome() internal view returns (uint256) {
        return IAaveV3Pool(aavePool()).getReserveNormalizedIncome(underlying());
    }

    function getTokensIn() public view override returns (address[] memory res) {
        return ArrayLib.create(underlying(), yieldBearingToken());
    }

    function getTokensOut() public view override returns (address[] memory res) {
        return ArrayLib.create(underlying(), yieldBearingToken());
    }

    function isValidTokenIn(address token) public view override returns (bool) {
        return token == underlying() || token == yieldBearingToken();
    }

    function isValidTokenOut(address token) public view override returns (bool) {
        return token == underlying() || token == yieldBearingToken();
    }

    function assetInfo() external view returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        address _underlying = underlying();
        return (AssetType.TOKEN, _underlying, IERC20Metadata(_underlying).decimals());
    }
}
