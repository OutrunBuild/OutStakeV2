// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    ReentrancyGuardTransientUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardTransientUpgradeable.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SYBaseUpgradeable} from "../../src/yield/SYBaseUpgradeable.sol";
import {ArrayLib} from "../../src/libraries/ArrayLib.sol";
import {ProxyTestHelper} from "./helpers/ProxyTestHelper.sol";

contract SYUpgradeableMockToken is ERC20 {
    constructor() ERC20("Yield Token", "YBT") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract TestSYUpgradeable is SYBaseUpgradeable {
    bool public reentryBlocked;

    function initialize(string memory name_, string memory symbol_, address token_, address owner_)
        external
        initializer
    {
        __SYBase_init(name_, symbol_, token_, owner_);
    }

    function _deposit(address, uint256 amountDeposited) internal override returns (uint256) {
        if (!reentryBlocked) {
            try this.redeem(address(this), 1, yieldBearingToken(), 0, true) {}
            catch (bytes memory reason) {
                bytes4 selector;
                assembly {
                    selector := mload(add(reason, 0x20))
                }
                reentryBlocked = selector == ReentrancyGuardTransientUpgradeable.ReentrancyGuardReentrantCall.selector;
            }
        }
        return amountDeposited;
    }

    function _redeem(address receiver, address tokenOut, uint256 amountSharesToRedeem)
        internal
        override
        returns (uint256)
    {
        IERC20(tokenOut).transfer(receiver, amountSharesToRedeem);
        return amountSharesToRedeem;
    }

    function exchangeRate() public pure override returns (uint256) {
        return 1e18;
    }

    function _previewDeposit(address, uint256 amountTokenToDeposit) internal pure override returns (uint256) {
        return amountTokenToDeposit;
    }

    function _previewRedeem(address, uint256 amountSharesToRedeem) internal pure override returns (uint256) {
        return amountSharesToRedeem;
    }

    function getTokensIn() public view override returns (address[] memory) {
        return ArrayLib.create(yieldBearingToken());
    }

    function getTokensOut() public view override returns (address[] memory) {
        return ArrayLib.create(yieldBearingToken());
    }

    function isValidTokenIn(address token) public view override returns (bool) {
        return token == yieldBearingToken();
    }

    function isValidTokenOut(address token) public view override returns (bool) {
        return token == yieldBearingToken();
    }

    function assetInfo() external view returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        return (AssetType.TOKEN, yieldBearingToken(), decimals());
    }
}

contract TestSYUpgradeableV2 is TestSYUpgradeable {
    function version() external pure returns (uint256) {
        return 2;
    }
}

contract SYUpgradeableTest is Test {
    address internal owner = address(0xA11CE);
    address internal user = address(0xB0B);

    SYUpgradeableMockToken internal token;
    TestSYUpgradeable internal sy;

    function setUp() external {
        token = new SYUpgradeableMockToken();
        sy = _deploySY();
    }

    function testSYBaseInitializerSetsOwnerMetadataAndYieldBearingToken() external {
        assertEq(sy.name(), "SY Token");
        assertEq(sy.symbol(), "SYT");
        assertEq(sy.decimals(), 18);
        assertEq(sy.owner(), owner);
        assertEq(sy.yieldBearingToken(), address(token));
    }

    function testSYBaseInitializerCannotRunTwice() external {
        vm.expectRevert();
        sy.initialize("x", "x", address(token), owner);
    }

    function testSYBaseZeroYieldBearingTokenReverts() external {
        TestSYUpgradeable implementation = new TestSYUpgradeable();
        vm.expectRevert();
        ProxyTestHelper.deploy(
            address(implementation),
            abi.encodeCall(TestSYUpgradeable.initialize, ("SY Token", "SYT", address(0), owner))
        );
    }

    function testSYBaseOwnerCanUpgrade() external {
        token.mint(user, 10e18);
        vm.startPrank(user);
        token.approve(address(sy), 10e18);
        sy.deposit(user, address(token), 10e18, 0);
        vm.stopPrank();

        TestSYUpgradeableV2 implementationV2 = new TestSYUpgradeableV2();
        vm.prank(owner);
        sy.upgradeToAndCall(address(implementationV2), "");

        assertEq(sy.balanceOf(user), 10e18);
        assertEq(TestSYUpgradeableV2(payable(address(sy))).version(), 2);
    }

    function testSYBaseNonOwnerCannotUpgrade() external {
        TestSYUpgradeableV2 implementationV2 = new TestSYUpgradeableV2();
        vm.prank(user);
        vm.expectRevert();
        sy.upgradeToAndCall(address(implementationV2), "");
    }

    function testDepositRedeemStillUseTransientNonReentrantGuard() external {
        token.mint(user, 10e18);
        vm.startPrank(user);
        token.approve(address(sy), 10e18);
        sy.deposit(user, address(token), 10e18, 0);
        sy.redeem(user, 5e18, address(token), 0, false);
        vm.stopPrank();

        assertTrue(sy.reentryBlocked());
        assertEq(sy.balanceOf(user), 5e18);
        assertEq(token.balanceOf(user), 5e18);
    }

    function _deploySY() internal returns (TestSYUpgradeable) {
        TestSYUpgradeable implementation = new TestSYUpgradeable();
        return TestSYUpgradeable(
            payable(ProxyTestHelper.deploy(
                    address(implementation),
                    abi.encodeCall(TestSYUpgradeable.initialize, ("SY Token", "SYT", address(token), owner))
                ))
        );
    }
}
