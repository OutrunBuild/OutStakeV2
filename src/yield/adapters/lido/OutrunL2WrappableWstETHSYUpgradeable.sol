// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

// L2 SY adapter where stETH exists natively on the L2 and can be wrapped/unwrapped
// against wstETH locally. Unlike OutrunL2WstETHSY, this adapter performs actual
// wrap/unwrap of stETH ↔ wstETH on-chain. The exchange rate comes from the L2
// stETH contract.

import {SYBaseUpgradeable} from "../../SYBaseUpgradeable.sol";
import {ArrayLib} from "../../../libraries/ArrayLib.sol";
import {IL2StETH} from "../../../integrations/lido/interfaces/IL2StETH.sol";

contract OutrunL2WrappableWstETHSYUpgradeable is SYBaseUpgradeable {
    /// @custom:storage-location erc7201:outrun.storage.OutrunL2WrappableWstETHSY
    // forge-lint: disable-next-line(pascal-case-struct)
    struct OutrunL2WrappableWstETHSYStorage {
        address STETH;
        // The asset this SY ultimately represents on Ethereum mainnet
        // (for cross-chain position accounting).
        address underlyingAssetOnEthAddr;
        uint8 underlyingAssetOnEthDecimals;
    }

    // keccak256(abi.encode(uint256(keccak256("outrun.storage.OutrunL2WrappableWstETHSY")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant OUTRUN_L2_WRAPPABLE_WST_ETH_SY_STORAGE_LOCATION =
        0x9da4bc70408d68d126efeec83eb110f8384c649e456fbb92edf8e08a726b7a00;

    /// @notice Initializes the SY adapter with L2 stETH/wstETH wrap capability.
    /// @param owner_ The contract owner address.
    /// @param stETH_ Address of the L2 stETH token.
    /// @param wstETH_ Address of the wstETH yield-bearing token.
    /// @param underlyingAssetOnEthAddr_ Address of the underlying asset on Ethereum mainnet (for cross-chain accounting).
    /// @param underlyingAssetOnEthDecimals_ Decimals of the underlying asset on Ethereum mainnet.
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

    /// @notice Returns the address of the L2 stETH token.
    /// @return The L2 stETH token address.
    function STETH() public view returns (address) {
        return _getStorage().STETH;
    }

    // If depositing stETH: unwrap to get wstETH shares.
    // If depositing wstETH: 1:1 (already the yield-bearing token).
    /// @notice Deposits stETH or wstETH: stETH is unwrapped to wstETH shares, wstETH is taken 1:1.
    /// @param tokenIn The input token address (stETH or wstETH).
    /// @param amountDeposited The amount of the input token deposited.
    /// @return amountSharesOut The amount of wstETH shares received.
    function _deposit(address tokenIn, uint256 amountDeposited) internal override returns (uint256 amountSharesOut) {
        address _STETH = STETH();
        if (tokenIn == _STETH) amountSharesOut = IL2StETH(_STETH).unwrap(amountDeposited);
        else amountSharesOut = amountDeposited;
    }

    // slither-disable-next-line reentrancy-no-eth
    // If redeeming to stETH: wrap wstETH shares into stETH and transfer.
    // If redeeming to wstETH: transfer directly.
    /// @notice Redeems wstETH shares: wraps to stETH for transfer, or transfers wstETH directly.
    /// @param receiver The address receiving the output tokens.
    /// @param tokenOut The output token address (stETH or wstETH).
    /// @param amountSharesToRedeem The amount of wstETH shares to redeem.
    /// @return amountTokenOut The amount of output tokens sent to the receiver.
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

    // Uses the L2 stETH contract's getTokensByShares to compute the
    // wstETH→stETH exchange rate.
    /// @notice Returns the stETH amount for 1 wstETH using the L2 stETH.getTokensByShares.
    /// @return res The amount of stETH equivalent to 1 wstETH (scaled by 1e18).
    function exchangeRate() public view override returns (uint256 res) {
        return IL2StETH(STETH()).getTokensByShares(1 ether);
    }

    /// @notice Previews the amount of wstETH shares that would be received for depositing a given token.
    /// @param tokenIn The input token address.
    /// @param amountTokenToDeposit The amount of the input token to deposit.
    /// @return The expected amount of wstETH shares received.
    function _previewDeposit(address tokenIn, uint256 amountTokenToDeposit) internal view override returns (uint256) {
        address _STETH = STETH();
        if (tokenIn == _STETH) return IL2StETH(_STETH).getSharesByTokens(amountTokenToDeposit);
        return amountTokenToDeposit;
    }

    /// @notice Previews the amount of output tokens that would be received for redeeming wstETH shares.
    /// @param tokenOut The output token address.
    /// @param amountSharesToRedeem The amount of wstETH shares to redeem.
    /// @return The expected amount of output tokens received.
    function _previewRedeem(address tokenOut, uint256 amountSharesToRedeem) internal view override returns (uint256) {
        address _STETH = STETH();
        if (tokenOut == _STETH) return IL2StETH(_STETH).getTokensByShares(amountSharesToRedeem);
        return amountSharesToRedeem;
    }

    /// @notice Returns the list of accepted input tokens.
    /// @return res Array containing stETH and wstETH addresses.
    function getTokensIn() public view override returns (address[] memory res) {
        return ArrayLib.create(STETH(), yieldBearingToken());
    }

    /// @notice Returns the list of accepted output tokens.
    /// @return res Array containing stETH and wstETH addresses.
    function getTokensOut() public view override returns (address[] memory res) {
        return ArrayLib.create(STETH(), yieldBearingToken());
    }

    /// @notice Checks whether a token is accepted as input.
    /// @param token The token address to check.
    /// @return True if the token is stETH or wstETH.
    function isValidTokenIn(address token) public view override returns (bool) {
        return token == STETH() || token == yieldBearingToken();
    }

    /// @notice Checks whether a token is accepted as output.
    /// @param token The token address to check.
    /// @return True if the token is stETH or wstETH.
    function isValidTokenOut(address token) public view override returns (bool) {
        return token == STETH() || token == yieldBearingToken();
    }

    /// @notice Returns the asset type and details of the underlying Ethereum mainnet asset this SY represents.
    /// @return assetType Always TOKEN.
    /// @return assetAddress The underlying asset address on Ethereum mainnet.
    /// @return assetDecimals The decimals of the underlying asset on Ethereum mainnet.
    function assetInfo() external view returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        OutrunL2WrappableWstETHSYStorage storage $ = _getStorage();
        return (AssetType.TOKEN, $.underlyingAssetOnEthAddr, $.underlyingAssetOnEthDecimals);
    }
}
