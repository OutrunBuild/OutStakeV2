// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {OutrunUniversalAssetsUpgradeable} from "../../src/assets/base/OutrunUniversalAssetsUpgradeable.sol";
import {IOutrunStakeManager} from "../../src/position/interfaces/IOutrunStakeManager.sol";
import {OutrunL2StakedTokenSYUpgradeable} from "../../src/yield/OutrunL2StakedTokenSYUpgradeable.sol";
import {OutrunStakingPositionUpgradeable} from "../../src/position/OutrunStakingPositionUpgradeable.sol";
import {MockLzEndpoint} from "./helpers/OFTTestHelper.sol";
import {ProxyTestHelper} from "./helpers/ProxyTestHelper.sol";
import {MockSY, MockERC20, MockUAsset} from "./helpers/PositionTestMocks.sol";
import {MockPositionUUPSV2} from "./mocks/MockUUPSVersion.sol";

contract PositionMockToken is ERC20 {
    constructor() ERC20("Yield Token", "YBT") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract PositionMockOracle {
    function getExchangeRate() external pure returns (uint256) {
        return 1e18;
    }
}

contract OutrunStakingPositionUpgradeableTest is Test {
    address internal owner = address(0xA11CE);
    address internal user = address(0xB0B);
    address internal revenuePool = address(0xFEE);
    address internal keeper = address(0xC0FFEE);

    PositionMockToken internal token;
    OutrunL2StakedTokenSYUpgradeable internal sy;
    OutrunUniversalAssetsUpgradeable internal uAsset;
    OutrunStakingPositionUpgradeable internal position;

    MockERC20 internal mixedUnderlying;
    MockSY internal mixedSy;
    MockUAsset internal mixedUAsset;
    OutrunStakingPositionUpgradeable internal mixedPosition;

    function setUp() external {
        token = new PositionMockToken();
        PositionMockOracle oracle = new PositionMockOracle();

        OutrunL2StakedTokenSYUpgradeable syImpl = new OutrunL2StakedTokenSYUpgradeable();
        sy = OutrunL2StakedTokenSYUpgradeable(
            payable(ProxyTestHelper.deploy(
                    address(syImpl),
                    abi.encodeCall(
                        OutrunL2StakedTokenSYUpgradeable.initialize,
                        ("SY Token", "SYT", owner, address(token), address(oracle), address(token), 18)
                    )
                ))
        );

        MockLzEndpoint endpoint = new MockLzEndpoint();
        OutrunUniversalAssetsUpgradeable uAssetImpl = new OutrunUniversalAssetsUpgradeable(18, address(endpoint));
        uAsset = OutrunUniversalAssetsUpgradeable(
            ProxyTestHelper.deploy(
                address(uAssetImpl),
                abi.encodeCall(OutrunUniversalAssetsUpgradeable.initialize, ("UAsset", "UAST", 18, owner))
            )
        );

        OutrunStakingPositionUpgradeable positionImpl = new OutrunStakingPositionUpgradeable();
        position = OutrunStakingPositionUpgradeable(
            ProxyTestHelper.deploy(
                address(positionImpl),
                abi.encodeCall(
                    OutrunStakingPositionUpgradeable.initialize,
                    (owner, 1, revenuePool, address(sy), address(uAsset), keeper)
                )
            )
        );

        vm.prank(owner);
        uAsset.setMintingCap(address(position), type(uint256).max);

        token.mint(user, 100e18);
        vm.startPrank(user);
        token.approve(address(sy), type(uint256).max);
        sy.deposit(user, address(token), 100e18, 0);
        sy.approve(address(position), type(uint256).max);
        vm.stopPrank();
    }

    function testInitializeSetsOwnerSyUAssetRevenuePoolMinStake() external {
        assertEq(position.owner(), owner);
        assertEq(position.SY(), address(sy));
        assertEq(position.uAsset(), address(uAsset));
        assertEq(position.revenuePool(), revenuePool);
        assertEq(position.keeper(), keeper);
        assertEq(position.minStake(), 1);
    }

    function testSyHasNoSetterAndRemainsFixed() external {
        (bool success,) = address(position).call(abi.encodeWithSignature("setSY(address)", address(0x1234)));

        assertFalse(success);
        assertEq(position.SY(), address(sy));
    }

    function testInitializeCannotRunTwice() external {
        vm.expectRevert();
        position.initialize(owner, 1, revenuePool, address(sy), address(uAsset), keeper);
    }

    function testInitializeRevertsWhenKeeperIsZero() external {
        OutrunStakingPositionUpgradeable positionImpl = new OutrunStakingPositionUpgradeable();

        vm.expectRevert(IOutrunStakeManager.ZeroInput.selector);
        ProxyTestHelper.deploy(
            address(positionImpl),
            abi.encodeCall(
                OutrunStakingPositionUpgradeable.initialize,
                (owner, 1, revenuePool, address(sy), address(uAsset), address(0))
            )
        );
    }

    function testKeepRedeemWorksWithInitializerKeeper() external {
        vm.prank(user);
        (uint256 positionId,) = position.stake(10e18, 30, user, keeper);

        vm.warp(block.timestamp + 31 days);

        vm.startPrank(keeper);
        uAsset.approve(address(position), 10e18);
        (uint256 burned, uint256 keeperPrincipalSY, uint256 ownerExcessSY) =
            position.keepRedeem(positionId, 10e18, keeper);
        vm.stopPrank();

        assertEq(burned, 10e18);
        assertEq(keeperPrincipalSY, 10e18);
        assertEq(ownerExcessSY, 0);
        assertEq(sy.balanceOf(keeper), 10e18);
        assertEq(uAsset.balanceOf(keeper), 0);
    }

    function testStakeThroughProxyAndUpgradePreservesState() external {
        vm.prank(user);
        (uint256 positionId, uint256 minted) = position.stake(10e18, 30, user, user);

        assertEq(positionId, 1);
        assertEq(minted, 10e18);
        assertEq(position.syTotalStaking(), 10e18);
        assertEq(uAsset.balanceOf(user), 10e18);

        MockPositionUUPSV2 implementationV2 = new MockPositionUUPSV2();
        vm.prank(owner);
        position.upgradeToAndCall(address(implementationV2), "");

        assertEq(position.syTotalStaking(), 10e18);
        assertEq(position.SY(), address(sy));
        assertEq(MockPositionUUPSV2(address(position)).version(), 2);
    }

    function testNonOwnerCannotUpgrade() external {
        MockPositionUUPSV2 implementationV2 = new MockPositionUUPSV2();
        vm.prank(user);
        vm.expectRevert();
        position.upgradeToAndCall(address(implementationV2), "");
    }

    function testRedeemDirectSYHonorsMinTokenOut() external {
        vm.prank(user);
        (uint256 positionId,) = position.stake(10e18, 30, user, user);

        vm.warp(block.timestamp + 31 days);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IOutrunStakeManager.InsufficientTokenOut.selector, 10e18, 10e18 + 1));
        position.redeem(positionId, 10e18, user, address(sy), 10e18 + 1);

        (, uint256 syStaked, uint256 uAssetMinted,,) = position.positions(positionId);
        assertEq(syStaked, 10e18);
        assertEq(uAssetMinted, 10e18);
        assertEq(sy.balanceOf(user), 90e18);
        assertEq(sy.balanceOf(address(position)), 10e18);
        assertEq(uAsset.balanceOf(user), 10e18);
    }

    function testMixedDecimalsStakeMintsUAssetInEighteenDecimals() external {
        _setupMixedDecimalsPosition();

        assertEq(mixedPosition.previewStake(1e6), 1e18);

        vm.prank(user);
        (uint256 positionId, uint256 minted) = mixedPosition.stake(1e6, 30, user, user);

        (, uint256 syStaked, uint256 uAssetMinted,,) = mixedPosition.positions(positionId);
        assertEq(minted, 1e18);
        assertEq(syStaked, 1e6);
        assertEq(uAssetMinted, 1e18);
        assertEq(mixedUAsset.balanceOf(user), 1e18);
    }

    function testMixedDecimalsPreviewsStakeAndWrapStakeInUAssetUnits() external {
        _setupMixedDecimalsPosition();

        assertEq(mixedPosition.previewStake(1e6), 1e18);
        assertEq(mixedPosition.previewWrapStake(1e6), 1e18);
    }

    function testMixedDecimalsDrawUAssetUsesEighteenDecimalsAfterRateIncrease() external {
        _setupMixedDecimalsPosition();

        vm.prank(user);
        (uint256 positionId,) = mixedPosition.stake(1e6, 30, user, user);

        mixedSy.setExchangeRate(15e17);

        assertEq(mixedPosition.previewDrawUAsset(positionId), 5e17);

        vm.prank(user);
        uint256 drawn = mixedPosition.drawUAsset(positionId, user);

        (, uint256 syStaked, uint256 uAssetMinted,,) = mixedPosition.positions(positionId);
        assertEq(drawn, 5e17);
        assertEq(syStaked, 1e6);
        assertEq(uAssetMinted, 15e17);
        assertEq(mixedUAsset.balanceOf(user), 15e17);
    }

    function testMixedDecimalsWrapRedeemConvertsEighteenDecimalsUAssetToSixDecimalsSY() external {
        _setupMixedDecimalsPosition();

        vm.prank(user);
        uint256 minted = mixedPosition.wrapStake(1e6, user);

        assertEq(minted, 1e18);
        assertEq(mixedPosition.previewWrapRedeem(1e18, address(mixedSy)), 1e6);

        vm.prank(user);
        mixedUAsset.approve(address(mixedPosition), 1e18);

        vm.prank(user);
        uint256 amountOut = mixedPosition.wrapRedeem(1e18, user, address(mixedSy), 1e6);

        assertEq(amountOut, 1e6);
        assertEq(mixedSy.balanceOf(user), 10e6);
        assertEq(mixedUAsset.balanceOf(user), 0);
        assertEq(mixedPosition.syWrapStaking(), 0);
        assertEq(mixedPosition.wrapUAssetDebt(), 0);
    }

    function testMixedDecimalsWrapRedeemRevertsWhenDustUAssetRoundsToZeroSY() external {
        _setupMixedDecimalsPosition();

        vm.prank(user);
        uint256 minted = mixedPosition.wrapStake(1e6, user);

        uint256 syWrapStakingBefore = mixedPosition.syWrapStaking();
        uint256 syTotalStakingBefore = mixedPosition.syTotalStaking();
        uint256 wrapUAssetDebtBefore = mixedPosition.wrapUAssetDebt();
        uint256 userSYBefore = mixedSy.balanceOf(user);
        uint256 userUAssetBefore = mixedUAsset.balanceOf(user);

        vm.prank(user);
        mixedUAsset.approve(address(mixedPosition), 1);

        vm.prank(user);
        vm.expectRevert(IOutrunStakeManager.ZeroInput.selector);
        mixedPosition.wrapRedeem(1, user, address(mixedSy), 0);

        assertEq(minted, 1e18);
        assertEq(syWrapStakingBefore, 1e6);
        assertEq(syTotalStakingBefore, 1e6);
        assertEq(wrapUAssetDebtBefore, 1e18);
        assertEq(mixedPosition.syWrapStaking(), syWrapStakingBefore);
        assertEq(mixedPosition.syTotalStaking(), syTotalStakingBefore);
        assertEq(mixedPosition.wrapUAssetDebt(), wrapUAssetDebtBefore);
        assertEq(mixedSy.balanceOf(user), userSYBefore);
        assertEq(mixedUAsset.balanceOf(user), userUAssetBefore);
    }

    function testRedeemUpdatesPositionStateBeforeRepay() external {
        _setupMixedDecimalsPosition();

        vm.prank(user);
        (uint256 positionId,) = mixedPosition.stake(1e6, 30, user, user);

        vm.warp(block.timestamp + 31 days);

        vm.prank(user);
        mixedUAsset.approve(address(mixedPosition), 5e17);
        mixedUAsset.probePositionDuringRepay(mixedPosition, positionId);

        vm.prank(user);
        mixedPosition.redeem(positionId, 5e5, user, address(mixedSy), 5e5);

        (, uint256 syStakedDuringRepay, uint256 uAssetMintedDuringRepay,,) = mixedPosition.positions(positionId);
        assertEq(syStakedDuringRepay, 5e5);
        assertEq(uAssetMintedDuringRepay, 5e17);
        assertEq(mixedUAsset.syStakedDuringRepay(), 5e5);
        assertEq(mixedUAsset.uAssetMintedDuringRepay(), 5e17);
        assertEq(mixedUAsset.syTotalStakingDuringRepay(), 5e5);
    }

    function testWrapRedeemUpdatesWrapPoolStateBeforeRepay() external {
        _setupMixedDecimalsPosition();

        vm.prank(user);
        mixedPosition.wrapStake(1e6, user);

        vm.prank(user);
        mixedUAsset.approve(address(mixedPosition), 5e17);
        mixedUAsset.probePositionDuringRepay(mixedPosition, 0);

        vm.prank(user);
        mixedPosition.wrapRedeem(5e17, user, address(mixedSy), 5e5);

        assertEq(mixedUAsset.syTotalStakingDuringRepay(), 5e5);
        assertEq(mixedUAsset.syWrapStakingDuringRepay(), 5e5);
        assertEq(mixedUAsset.wrapUAssetDebtDuringRepay(), 5e17);
    }

    function testMixedDecimalsKeepRedeemSplitsKeeperPrincipalAndOwnerExcessInSYUnits() external {
        _setupMixedDecimalsPosition();

        vm.prank(user);
        (uint256 positionId,) = mixedPosition.stake(1e6, 30, user, keeper);

        mixedSy.setExchangeRate(2e18);
        vm.warp(block.timestamp + 31 days);

        vm.startPrank(keeper);
        mixedUAsset.approve(address(mixedPosition), type(uint256).max);
        (uint256 burned, uint256 keeperPrincipalSY, uint256 ownerExcessSY) =
            mixedPosition.keepRedeem(positionId, 1e18, keeper);
        vm.stopPrank();

        assertEq(burned, 1e18);
        assertEq(keeperPrincipalSY, 5e5);
        assertEq(ownerExcessSY, 5e5);
        assertEq(mixedSy.balanceOf(keeper), 5e5);
        assertEq(mixedSy.balanceOf(user), 9_500000);
    }

    function testMixedDecimalsHarvestWrapYieldHarvestsOnlyExcessWithUpRounding() external {
        _setupMixedDecimalsPosition();

        vm.prank(user);
        uint256 minted = mixedPosition.wrapStake(1_000001, user);
        assertEq(minted, 1000001e12);

        mixedSy.setExchangeRate(3e18);

        vm.prank(owner);
        uint256 harvested = mixedPosition.harvestWrapYield(address(mixedSy), 0);

        uint256 expectedDebtInSY = 333334;
        uint256 expectedHarvest = 666667;
        assertEq(harvested, expectedHarvest);
        assertEq(mixedPosition.syWrapStaking(), expectedDebtInSY);
        assertEq(mixedPosition.wrapUAssetDebt(), minted);
        assertEq(mixedSy.balanceOf(revenuePool), expectedHarvest);
    }

    function _setupMixedDecimalsPosition() internal {
        mixedUnderlying = new MockERC20("Mock USDC", "mUSDC");
        mixedUnderlying.setDecimals(6);
        mixedSy = new MockSY(address(mixedUnderlying));
        mixedSy.setDecimals(6, 6);
        mixedUAsset = new MockUAsset();

        mixedPosition = OutrunStakingPositionUpgradeable(
            ProxyTestHelper.deploy(
                address(new OutrunStakingPositionUpgradeable()),
                abi.encodeCall(
                    OutrunStakingPositionUpgradeable.initialize,
                    (owner, 1, revenuePool, address(mixedSy), address(mixedUAsset), keeper)
                )
            )
        );

        mixedUAsset.setMintingCap(address(mixedPosition), type(uint256).max);
        mixedSy.mintShares(user, 10e6);

        vm.prank(user);
        mixedSy.approve(address(mixedPosition), type(uint256).max);
    }
}
