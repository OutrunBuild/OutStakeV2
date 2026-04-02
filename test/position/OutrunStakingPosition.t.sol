// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {OutrunStakingPosition} from "../../src/position/OutrunStakingPosition.sol";
import {IOutrunStakeManager} from "../../src/position/interfaces/IOutrunStakeManager.sol";
import {IStandardizedYield} from "../../src/yield/interfaces/IStandardizedYield.sol";
import {IUniversalAssets} from "../../src/assets/interfaces/IUniversalAssets.sol";
import {OutrunERC20} from "../../src/assets/base/OutrunERC20.sol";

contract MockSY is OutrunERC20, IStandardizedYield {
    address internal immutable underlying;
    uint256 internal rate;

    constructor(address underlying_) OutrunERC20("Mock SY", "mSY", 18) {
        underlying = underlying_;
        rate = 1e18;
    }

    function setExchangeRate(uint256 newRate) external {
        rate = newRate;
    }

    function mintShares(address receiver, uint256 amount) external {
        _mint(receiver, amount);
    }

    function deposit(address receiver, address, uint256 amountTokenToDeposit, uint256)
        external
        payable
        returns (uint256 amountSharesOut)
    {
        amountSharesOut = amountTokenToDeposit;
        _mint(receiver, amountSharesOut);
    }

    function redeem(
        address receiver,
        uint256 amountSharesToRedeem,
        address tokenOut,
        uint256,
        bool burnFromInternalBalance
    ) external returns (uint256 amountTokenOut) {
        if (burnFromInternalBalance) {
            _burn(address(this), amountSharesToRedeem);
        } else {
            _burn(msg.sender, amountSharesToRedeem);
        }

        amountTokenOut = amountSharesToRedeem;
        if (tokenOut == address(this)) {
            _mint(receiver, amountTokenOut);
        } else {
            MockERC20(tokenOut).mint(receiver, amountTokenOut);
        }
    }

    function exchangeRate() external view returns (uint256 res) {
        res = rate;
    }

    function yieldBearingToken() external view returns (address) {
        return underlying;
    }

    function getTokensIn() external view returns (address[] memory res) {
        res = new address[](1);
        res[0] = underlying;
    }

    function getTokensOut() external view returns (address[] memory res) {
        res = new address[](1);
        res[0] = address(this);
    }

    function isValidTokenIn(address token) external view returns (bool) {
        return token == underlying || token == address(this);
    }

    function isValidTokenOut(address token) external view returns (bool) {
        return token == address(this) || token == underlying;
    }

    function previewDeposit(address, uint256 amountTokenToDeposit) external pure returns (uint256 amountSharesOut) {
        amountSharesOut = amountTokenToDeposit;
    }

    function previewRedeem(address, uint256 amountSharesToRedeem) external pure returns (uint256 amountTokenOut) {
        amountTokenOut = amountSharesToRedeem;
    }

    function assetInfo() external view returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        assetType = AssetType.TOKEN;
        assetAddress = underlying;
        assetDecimals = 18;
    }
}

contract MockERC20 is OutrunERC20 {
    constructor(string memory name_, string memory symbol_) OutrunERC20(name_, symbol_, 18) {}

    function mint(address receiver, uint256 amount) external {
        _mint(receiver, amount);
    }
}

contract MockUAsset is OutrunERC20, IUniversalAssets {
    mapping(address minter => MintingStatus) public mintingStatusTable;

    constructor() OutrunERC20("Mock UAsset", "mUAsset", 18) {}

    function checkMintableAmount(address minter) external view returns (uint256 amountInMintable) {
        MintingStatus storage status = mintingStatusTable[minter];
        amountInMintable = status.mintingCap > status.amountInMinted ? status.mintingCap - status.amountInMinted : 0;
    }

    function setMintingCap(address minter, uint256 mintingCap) public {
        mintingStatusTable[minter].mintingCap = mintingCap;
    }

    function revokeMinter(address minter) external {
        mintingStatusTable[minter].mintingCap = 0;
    }

    function mint(address receiver, uint256 amount) external {
        MintingStatus storage status = mintingStatusTable[msg.sender];
        require(status.amountInMinted + amount <= status.mintingCap, ReachMintCap());
        status.amountInMinted += amount;
        _mint(receiver, amount);
    }

    function repay(address account, uint256 amount) external {
        MintingStatus storage status = mintingStatusTable[msg.sender];
        require(status.amountInMinted >= amount, ReachBurnCap());
        _spendAllowance(account, msg.sender, amount);
        status.amountInMinted -= amount;
        _burn(account, amount);
    }
}

contract OutrunStakingPositionTest is Test {
    bytes4 internal constant POSITION_ACCESS_DENIED_SELECTOR = bytes4(keccak256("PositionAccessDenied()"));
    uint256 internal constant LARGE_AMOUNT = uint256(type(uint128).max) + 7;

    MockERC20 internal underlying;
    MockSY internal sy;
    MockUAsset internal uAsset;
    OutrunStakingPosition internal position;

    address internal owner = address(0xA11CE);
    address internal keeper = address(0xB0B);
    address internal keeper2 = address(0xB0C);
    address internal revenuePool = address(0xFEE);

    function setUp() external {
        underlying = new MockERC20("Mock Asset", "mAST");
        sy = new MockSY(address(underlying));
        uAsset = new MockUAsset();

        position = new OutrunStakingPosition(owner, 1, revenuePool, address(sy), address(uAsset));

        uAsset.setMintingCap(address(position), type(uint256).max);

        vm.prank(owner);
        position.setKeeper(keeper);

        sy.mintShares(owner, 1_000e18);
        sy.mintShares(keeper, 1_000e18);
        sy.mintShares(keeper2, 1_000e18);

        vm.prank(owner);
        sy.approve(address(position), type(uint256).max);

        vm.prank(keeper);
        sy.approve(address(position), type(uint256).max);

        vm.prank(keeper2);
        sy.approve(address(position), type(uint256).max);
    }

    function testStakeDoesNotRequireLockupDurationConfig() external {
        OutrunStakingPosition freshPosition =
            new OutrunStakingPosition(owner, 1, revenuePool, address(sy), address(uAsset));
        uAsset.setMintingCap(address(freshPosition), type(uint256).max);

        sy.mintShares(owner, 100e18);

        vm.prank(owner);
        sy.approve(address(freshPosition), type(uint256).max);

        vm.prank(owner);
        (uint256 positionId, uint256 uAssetMinted) = freshPosition.stake(100e18, 3650, owner, owner);

        assertEq(positionId, 1);
        assertEq(uAssetMinted, 100e18);
    }

    function testOnlyPositionOwnerUsesUnifiedAccessError() external {
        vm.prank(owner);
        (uint256 positionId,) = position.stake(100e18, 30, owner, owner);

        vm.prank(keeper);
        vm.expectRevert(POSITION_ACCESS_DENIED_SELECTOR);
        position.drawUAsset(positionId, keeper);

        vm.prank(owner);
        vm.expectRevert(POSITION_ACCESS_DENIED_SELECTOR);
        position.drawUAsset(type(uint256).max, owner);
    }

    function testSetKeeperReplacesPreviousKeeper() external {
        vm.prank(owner);
        (uint256 positionId,) = position.stake(100e18, 30, owner, owner);

        vm.warp(block.timestamp + 31 days);
        sy.mintShares(address(position), 100e18);

        vm.prank(owner);
        assertTrue(uAsset.transfer(keeper2, 100e18));

        vm.prank(keeper2);
        uAsset.approve(address(position), type(uint256).max);

        vm.prank(owner);
        position.setKeeper(keeper2);

        vm.prank(keeper);
        vm.expectRevert(IOutrunStakeManager.PermissionDenied.selector);
        position.keepRedeem(positionId, 100e18, keeper);

        vm.prank(keeper2);
        position.keepRedeem(positionId, 100e18, keeper2);
    }

    function testStakeSupportsAmountBeyondUint128() external {
        sy.mintShares(owner, LARGE_AMOUNT);

        vm.prank(owner);
        (
            bool ok,
            bytes memory data
            // solhint-disable-next-line avoid-low-level-calls
        ) = address(position).call(
            abi.encodeWithSelector(IOutrunStakeManager.stake.selector, LARGE_AMOUNT, uint128(30), owner, owner)
        );

        assertTrue(ok, "stake missing");

        (uint256 positionId, uint256 uAssetMinted) = abi.decode(data, (uint256, uint256));
        (address positionOwner, uint256 syStaked, uint256 positionUAssetMinted,,) = position.positions(positionId);

        assertEq(positionOwner, owner);
        assertEq(syStaked, LARGE_AMOUNT);
        assertEq(positionUAssetMinted, LARGE_AMOUNT);
        assertEq(uAssetMinted, LARGE_AMOUNT);
        assertEq(uAsset.balanceOf(owner), LARGE_AMOUNT);
    }

    function testDrawUAssetTracksDebtBeyondUint128() external {
        sy.mintShares(owner, LARGE_AMOUNT);

        vm.prank(owner);
        // solhint-disable-next-line avoid-low-level-calls
        (bool staked, bytes memory stakeData) = address(position).call(
            abi.encodeWithSelector(IOutrunStakeManager.stake.selector, LARGE_AMOUNT, uint128(30), owner, owner)
        );
        assertTrue(staked, "stake missing");

        (uint256 positionId,) = abi.decode(stakeData, (uint256, uint256));
        sy.setExchangeRate(2e18);

        vm.prank(owner);
        uint256 drawAmount = position.drawUAsset(positionId, owner);

        (, uint256 syStaked, uint256 positionUAssetMinted,,) = position.positions(positionId);

        assertEq(drawAmount, LARGE_AMOUNT);
        assertEq(syStaked, LARGE_AMOUNT);
        assertEq(positionUAssetMinted, LARGE_AMOUNT * 2);
        assertEq(uAsset.balanceOf(owner), LARGE_AMOUNT * 2);
    }

    function testWrapStakeSupportsDebtBeyondUint128() external {
        sy.mintShares(owner, LARGE_AMOUNT);

        vm.prank(owner);
        (
            bool ok,
            bytes memory data
            // solhint-disable-next-line avoid-low-level-calls
        ) = address(position).call(abi.encodeWithSignature("wrapStake(uint256,address)", LARGE_AMOUNT, owner));

        assertTrue(ok, "wrapStake(uint256,...) missing");

        uint256 uAssetMinted = abi.decode(data, (uint256));

        assertEq(uAssetMinted, LARGE_AMOUNT);
        assertEq(position.syWrapStaking(), LARGE_AMOUNT);
        assertEq(position.wrapUAssetDebt(), LARGE_AMOUNT);
        assertEq(uAsset.balanceOf(owner), LARGE_AMOUNT);
    }

    function testStakeCreatesPositionAndMintsUAssetAtCurrentValue() external {
        vm.prank(owner);
        (uint256 positionId, uint256 uAssetMinted) = position.stake(100e18, 30, owner, owner);

        (address positionOwner, uint256 syStaked, uint256 positionUAssetMinted,,) = position.positions(positionId);

        assertEq(uAssetMinted, 100e18);
        assertEq(syStaked, 100e18);
        assertEq(positionUAssetMinted, 100e18);
        assertEq(positionOwner, owner);
        assertEq(uAsset.balanceOf(owner), 100e18);
    }

    function testStakeSeparatesPositionOwnerAndUAssetReceiver() external {
        address uAssetReceiver = address(0xBEEF);

        vm.prank(owner);
        (uint256 positionId, uint256 uAssetMinted) = position.stake(100e18, 30, owner, uAssetReceiver);

        (address positionOwner, uint256 syStaked, uint256 positionUAssetMinted,,) = position.positions(positionId);

        assertEq(positionOwner, owner);
        assertEq(syStaked, 100e18);
        assertEq(positionUAssetMinted, 100e18);
        assertEq(uAssetMinted, 100e18);
        assertEq(uAsset.balanceOf(owner), 0);
        assertEq(uAsset.balanceOf(uAssetReceiver), 100e18);
    }

    function testDrawUAssetMintsOnlyAppreciation() external {
        vm.prank(owner);
        (uint256 positionId,) = position.stake(100e18, 30, owner, owner);

        sy.setExchangeRate(12e17);

        vm.prank(owner);
        uint256 drawAmount = position.drawUAsset(positionId, owner);

        (, uint256 syStaked, uint256 positionUAssetMinted,,) = position.positions(positionId);

        assertEq(drawAmount, 20e18);
        assertEq(syStaked, 100e18);
        assertEq(positionUAssetMinted, 120e18);
        assertEq(uAsset.balanceOf(owner), 120e18);
    }

    function testRedeemBurnsProRataUAssetAndTransfersSY() external {
        vm.prank(owner);
        (uint256 positionId,) = position.stake(100e18, 30, owner, owner);

        sy.setExchangeRate(12e17);

        vm.prank(owner);
        position.drawUAsset(positionId, owner);

        vm.warp(block.timestamp + 31 days);

        vm.prank(owner);
        assertTrue(sy.transfer(address(position), 100e18));

        vm.prank(owner);
        uAsset.approve(address(position), type(uint256).max);

        vm.prank(owner);
        (uint256 uAssetBurned, uint256 syOut) = position.redeem(positionId, 50e18, owner, address(sy));

        (, uint256 syStaked, uint256 positionUAssetMinted,,) = position.positions(positionId);

        assertEq(uAssetBurned, 60e18);
        assertEq(syOut, 50e18);
        assertEq(syStaked, 50e18);
        assertEq(positionUAssetMinted, 60e18);
    }

    function testKeepRedeemSendsExcessToOwnerWithoutProtocolFee() external {
        vm.prank(owner);
        (uint256 positionId,) = position.stake(100e18, 30, owner, owner);

        sy.setExchangeRate(15e17);

        vm.warp(block.timestamp + 31 days);
        sy.mintShares(address(position), 100e18);

        vm.prank(owner);
        assertTrue(uAsset.transfer(keeper, 100e18));

        vm.prank(keeper);
        uAsset.approve(address(position), type(uint256).max);

        vm.prank(keeper);
        (uint256 uAssetBurned, uint256 keeperPrincipalSy, uint256 ownerExcessSy) =
            position.keepRedeem(positionId, 100e18, keeper);

        assertEq(uAssetBurned, 100e18);
        assertEq(keeperPrincipalSy, 66_666666666666666666);
        assertEq(ownerExcessSy, 33_333333333333333334);
        assertEq(sy.balanceOf(revenuePool), 0);
    }

    function testKeepRedeemUsesUAssetBurnInputInsteadOfSyRedeemed() external {
        vm.prank(owner);
        (uint256 positionId,) = position.stake(100e18, 30, owner, owner);

        sy.setExchangeRate(12e17);

        vm.prank(owner);
        position.drawUAsset(positionId, owner);

        vm.warp(block.timestamp + 31 days);
        sy.mintShares(address(position), 100e18);

        vm.prank(owner);
        assertTrue(uAsset.transfer(keeper, 60e18));

        vm.prank(keeper);
        uAsset.approve(address(position), type(uint256).max);

        vm.prank(keeper);
        (uint256 uAssetBurned, uint256 keeperPrincipalSy, uint256 ownerExcessSy) =
            position.keepRedeem(positionId, 60e18, keeper);

        (, uint256 syStaked, uint256 positionUAssetMinted,,) = position.positions(positionId);

        assertEq(uAssetBurned, 60e18);
        assertEq(syStaked, 50e18);
        assertEq(positionUAssetMinted, 60e18);
        assertEq(keeperPrincipalSy, 50e18);
        assertEq(ownerExcessSy, 0);
    }

    function testWrapStakeAndWrapRedeemStayOnPrincipalValue() external {
        vm.prank(owner);
        uint256 uAssetMinted = position.wrapStake(100e18, owner);

        assertEq(uAssetMinted, 100e18);
        assertEq(position.syWrapStaking(), 100e18);
        assertEq(position.wrapUAssetDebt(), 100e18);

        sy.setExchangeRate(15e17);

        vm.prank(owner);
        uAsset.approve(address(position), type(uint256).max);

        vm.prank(owner);
        uint256 syOut = position.wrapRedeem(40e18, owner, address(sy));

        assertEq(syOut, 26_666666666666666666);
        assertEq(position.syWrapStaking(), 73_333333333333333334);
        assertEq(position.wrapUAssetDebt(), 60e18);
    }

    function testRedeemToTokenOutDoesNotDoubleDecrementSyTotalStaking() external {
        vm.prank(owner);
        (uint256 positionId,) = position.stake(100e18, 30, owner, owner);

        vm.warp(block.timestamp + 31 days);

        vm.prank(owner);
        uAsset.approve(address(position), type(uint256).max);

        vm.prank(owner);
        (uint256 uAssetBurned, uint256 amountOut) = position.redeem(positionId, 40e18, owner, address(underlying));

        assertEq(uAssetBurned, 40e18);
        assertEq(amountOut, 40e18);
        assertEq(position.syTotalStaking(), 60e18);
    }

    function testWrapRedeemRevertsWhenRequestedSYExceedsWrapPoolShares() external {
        vm.prank(owner);
        position.wrapStake(100e18, owner);

        sy.setExchangeRate(8e17);

        vm.prank(owner);
        uAsset.approve(address(position), type(uint256).max);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IOutrunStakeManager.ExceedsWrapPoolBalance.selector, 125e18, 100e18));
        position.wrapRedeem(100e18, owner, address(sy));
    }

    function testHarvestWrapYieldTransfersProtocolRevenue() external {
        vm.prank(owner);
        position.wrapStake(90e18, owner);

        sy.setExchangeRate(12e17);

        vm.prank(owner);
        (
            bool ok,
            bytes memory data
            // solhint-disable-next-line avoid-low-level-calls
        ) = address(position).call(abi.encodeWithSignature("harvestWrapYield(address)", address(sy)));

        assertTrue(ok, "harvestWrapYield missing");

        uint256 harvested = abi.decode(data, (uint256));

        assertEq(harvested, 15e18);
        assertEq(sy.balanceOf(revenuePool), 15e18);
        assertEq(position.syWrapStaking(), 75e18);
        assertEq(position.syTotalStaking(), 75e18);
        assertEq(position.wrapUAssetDebt(), 90e18);
    }
}
