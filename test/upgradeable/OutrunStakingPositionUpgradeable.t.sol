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
}
