// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";

import {OutrunL2StakedTokenSYUpgradeable} from "../../src/yield/OutrunL2StakedTokenSYUpgradeable.sol";
import {OutrunStakedUsdsSYUpgradeable} from "../../src/yield/adapters/sky/OutrunStakedUsdsSYUpgradeable.sol";
import {ProxyTestHelper} from "./helpers/ProxyTestHelper.sol";
import {
    MockWstETH,
    MockUSDS,
    MockSUSDS,
    MockExchangeOracle,
    MockPositionManager
} from "./mocks/RouterPositionSyMocks.sol";

contract RouterPositionSyTest is Test {
    address internal constant OWNER = address(0xA11CE);
    address internal constant USER = address(0xB0B);

    uint256 internal constant STAKE_AMOUNT = 100 ether;

    MockWstETH internal wstETH;
    MockExchangeOracle internal oracle;
    OutrunL2StakedTokenSYUpgradeable internal sy;
    MockPositionManager internal position;

    function setUp() external {
        wstETH = new MockWstETH();
        oracle = new MockExchangeOracle();
        sy = OutrunL2StakedTokenSYUpgradeable(
            payable(ProxyTestHelper.deploy(
                    address(new OutrunL2StakedTokenSYUpgradeable()),
                    abi.encodeCall(
                        OutrunL2StakedTokenSYUpgradeable.initialize,
                        ("SY wstETH", "SYw", OWNER, address(wstETH), address(oracle), address(wstETH), 18)
                    )
                ))
        );
        position = new MockPositionManager(address(wstETH));
    }

    function test_GenesisStakeRedeemFullCycle() external {
        wstETH.mint(USER, STAKE_AMOUNT * 10);
        wstETH.mint(OWNER, STAKE_AMOUNT);

        // User deposits tokens into SY
        vm.prank(USER);
        wstETH.approve(address(sy), STAKE_AMOUNT);
        vm.prank(USER);
        uint256 sharesOut = sy.deposit(USER, address(wstETH), STAKE_AMOUNT, 0);

        assertEq(sharesOut, STAKE_AMOUNT);
        assertEq(sy.balanceOf(USER), STAKE_AMOUNT);

        // OWNER stakes wstETH into position directly
        vm.startPrank(OWNER);
        wstETH.approve(address(position), STAKE_AMOUNT);
        uint256 positionId = position.stake(OWNER, STAKE_AMOUNT);
        vm.stopPrank();

        assertEq(position.totalPositionUAsset(), STAKE_AMOUNT);

        // Transfer SY shares to OWNER for bookkeeping
        vm.prank(USER);
        sy.transfer(OWNER, sharesOut);

        // Redeem from position
        vm.prank(OWNER);
        uint256 redeemed = position.redeemAll(OWNER, positionId);

        assertGt(redeemed, 0);
        assertEq(position.totalPositionUAsset(), 0);

        uint256 expectedRedeem = (STAKE_AMOUNT * (10000 - 50)) / 10000;
        assertEq(redeemed, expectedRedeem);
    }

    function test_PartialRedemptionsPreserveAccounting() external {
        wstETH.mint(OWNER, STAKE_AMOUNT * 2);
        vm.startPrank(OWNER);
        wstETH.approve(address(position), STAKE_AMOUNT);

        uint256 positionId = position.stake(OWNER, STAKE_AMOUNT);

        uint256 firstRedeem = (STAKE_AMOUNT * 30) / 100;
        uint256 redeemed1 = position.redeem(OWNER, positionId, firstRedeem);

        uint256 expectedFirstRedeem = (firstRedeem * (10000 - 50)) / 10000;
        assertEq(redeemed1, expectedFirstRedeem);

        uint256 expectedRemaining = STAKE_AMOUNT - firstRedeem;
        (, uint256 remainingStake,,,,) = position.positions(positionId);
        assertEq(remainingStake, expectedRemaining);

        assertEq(position.totalPositionUAsset(), expectedRemaining);

        // Second partial redeem
        uint256 secondRedeem = (STAKE_AMOUNT * 30) / 100;
        uint256 redeemed2 = position.redeem(OWNER, positionId, secondRedeem);
        uint256 expectedSecondRedeem = (secondRedeem * (10000 - 50)) / 10000;
        assertEq(redeemed2, expectedSecondRedeem);

        uint256 finalRemaining = expectedRemaining - secondRedeem;
        (, remainingStake,,,,) = position.positions(positionId);
        assertEq(remainingStake, finalRemaining);
        assertEq(position.totalPositionUAsset(), finalRemaining);

        vm.stopPrank();
    }

    function test_ExchangeRateChangeMidCycle() external {
        wstETH.mint(USER, STAKE_AMOUNT * 10);

        vm.prank(USER);
        wstETH.approve(address(sy), STAKE_AMOUNT);
        vm.prank(USER);
        uint256 sharesOut = sy.deposit(USER, address(wstETH), STAKE_AMOUNT, 0);
        assertEq(sharesOut, STAKE_AMOUNT);

        // Exchange rate changes (yield accrual)
        oracle.setExchangeRate(1.1e18);
        uint256 newRate = sy.exchangeRate();
        assertEq(newRate, 1.1e18);

        assertEq(sy.balanceOf(USER), STAKE_AMOUNT);
    }

    function test_KeepRedeemDoesNotBlockOtherUsers() external {
        address user1 = address(0x1111);
        address user2 = address(0x2222);
        uint256 stake1 = 100 ether;
        uint256 stake2 = 50 ether;

        wstETH.mint(user1, stake1 * 2);
        wstETH.mint(user2, stake2 * 2);

        vm.prank(user1);
        wstETH.approve(address(position), stake1);
        vm.prank(user1);
        position.stake(user1, stake1);

        vm.prank(user2);
        wstETH.approve(address(position), stake2);
        vm.prank(user2);
        uint256 posId2 = position.stake(user2, stake2);

        // user1 redeems all
        vm.prank(user1);
        position.redeemAll(user1, 1);

        (, uint256 remainingStake,,,,) = position.positions(posId2);
        assertEq(remainingStake, stake2);
        assertEq(position.totalPositionUAsset(), stake2);
    }

    function test_RouterMultiProtocolRouting() external {
        MockUSDS usds = new MockUSDS();
        MockSUSDS sUSDS = new MockSUSDS(address(usds));

        OutrunStakedUsdsSYUpgradeable sy2 = OutrunStakedUsdsSYUpgradeable(
            payable(ProxyTestHelper.deploy(
                    address(new OutrunStakedUsdsSYUpgradeable()),
                    abi.encodeCall(OutrunStakedUsdsSYUpgradeable.initialize, (OWNER, address(usds), address(sUSDS)))
                ))
        );

        usds.mint(USER, STAKE_AMOUNT * 10);
        sUSDS.mintShares(USER, STAKE_AMOUNT);

        vm.startPrank(USER);
        usds.approve(address(sy2), type(uint256).max);
        sUSDS.approve(address(sy2), type(uint256).max);

        uint256 sharesOut = sy2.deposit(USER, address(usds), STAKE_AMOUNT, 0);
        assertEq(sharesOut, STAKE_AMOUNT);
        assertEq(sy2.balanceOf(USER), STAKE_AMOUNT);

        assertEq(sy.balanceOf(USER), 0, "first SY balance should be unaffected");

        vm.stopPrank();
    }
}
