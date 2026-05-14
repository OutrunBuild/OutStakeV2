// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {OFTReceipt, SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";

import {OutrunUniversalAssetsUpgradeable} from "../../src/assets/base/OutrunUniversalAssetsUpgradeable.sol";
import {MockLzEndpoint} from "./helpers/OFTTestHelper.sol";
import {MockUAssetUUPSV2, MockUAssetUUPSV2DifferentSharedDecimals} from "./mocks/MockUUPSVersion.sol";
import {ProxyTestHelper} from "./helpers/ProxyTestHelper.sol";

contract OutrunUniversalAssetsUpgradeableTest is Test {
    OutrunUniversalAssetsUpgradeable internal uAsset;
    MockLzEndpoint internal endpoint;

    address internal owner = address(0xA11CE);
    address internal minter = address(0xB0B);
    address internal receiver = address(0xCAFE);

    function setUp() external {
        endpoint = new MockLzEndpoint();
        OutrunUniversalAssetsUpgradeable implementation = new OutrunUniversalAssetsUpgradeable(18, address(endpoint));
        bytes memory initData = abi.encodeCall(
            OutrunUniversalAssetsUpgradeable.initialize, ("Omnichain Universal Assets ETH", "UETH", 18, owner)
        );
        uAsset = OutrunUniversalAssetsUpgradeable(ProxyTestHelper.deploy(address(implementation), initData));
    }

    function testInitializeSetsMetadataAndOwner() external {
        assertEq(uAsset.name(), "Omnichain Universal Assets ETH");
        assertEq(uAsset.symbol(), "UETH");
        assertEq(uAsset.decimals(), 18);
        assertEq(uAsset.owner(), owner);
    }

    function testInitializeRevertsWhenCalledTwice() external {
        vm.expectRevert();
        uAsset.initialize("x", "x", 18, owner);
    }

    function testImplementationCannotBeInitializedDirectly() external {
        OutrunUniversalAssetsUpgradeable implementation = new OutrunUniversalAssetsUpgradeable(18, address(endpoint));
        vm.expectRevert();
        implementation.initialize("x", "x", 18, owner);
    }

    function testDecimalsMustMatchConstructorLocalDecimals() external {
        OutrunUniversalAssetsUpgradeable implementation = new OutrunUniversalAssetsUpgradeable(18, address(endpoint));
        bytes memory initData = abi.encodeCall(OutrunUniversalAssetsUpgradeable.initialize, ("Bad", "BAD", 6, owner));
        vm.expectRevert(abi.encodeWithSelector(OutrunUniversalAssetsUpgradeable.DecimalsMismatch.selector, 18, 6));
        ProxyTestHelper.deploy(address(implementation), initData);
    }

    function testOwnerCanUpgradeAndStateSurvives() external {
        vm.prank(owner);
        uAsset.setMintingCap(minter, 100e18);

        uint256 amountReceivedBefore = _quoteAmountReceived(1e18);
        MockUAssetUUPSV2 implementationV2 = new MockUAssetUUPSV2(18, address(endpoint));
        vm.prank(owner);
        uAsset.upgradeToAndCall(address(implementationV2), "");

        assertEq(uAsset.checkMintableAmount(minter), 100e18);
        assertEq(uAsset.owner(), owner);
        assertEq(MockUAssetUUPSV2(address(uAsset)).version(), 2);
        assertEq(_quoteAmountReceived(1e18), amountReceivedBefore);
    }

    function testNonOwnerCannotUpgrade() external {
        OutrunUniversalAssetsUpgradeable implementationV2 = new OutrunUniversalAssetsUpgradeable(18, address(endpoint));
        vm.prank(minter);
        vm.expectRevert();
        uAsset.upgradeToAndCall(address(implementationV2), "");
    }

    function testOwnerCannotUpgradeToDifferentEndpoint() external {
        MockLzEndpoint otherEndpoint = new MockLzEndpoint();
        MockUAssetUUPSV2 implementationV2 = new MockUAssetUUPSV2(18, address(otherEndpoint));

        vm.prank(owner);
        vm.expectRevert(OutrunUniversalAssetsUpgradeable.InvalidOFTUpgradeConfig.selector);
        uAsset.upgradeToAndCall(address(implementationV2), "");
    }

    function testOwnerCannotUpgradeToDifferentLocalDecimals() external {
        MockUAssetUUPSV2 implementationV2 = new MockUAssetUUPSV2(6, address(endpoint));

        vm.prank(owner);
        vm.expectRevert(OutrunUniversalAssetsUpgradeable.InvalidOFTUpgradeConfig.selector);
        uAsset.upgradeToAndCall(address(implementationV2), "");
    }

    function testOwnerCannotUpgradeToDifferentDecimalConversionRate() external {
        MockUAssetUUPSV2DifferentSharedDecimals implementationV2 =
            new MockUAssetUUPSV2DifferentSharedDecimals(18, address(endpoint));

        vm.prank(owner);
        vm.expectRevert(OutrunUniversalAssetsUpgradeable.InvalidOFTUpgradeConfig.selector);
        uAsset.upgradeToAndCall(address(implementationV2), "");
    }

    function testMintRepayAndMintCapThroughProxy() external {
        vm.prank(owner);
        uAsset.setMintingCap(minter, 100e18);

        vm.prank(minter);
        uAsset.mint(receiver, 40e18);

        vm.prank(receiver);
        uAsset.approve(minter, 15e18);

        vm.prank(minter);
        uAsset.repay(receiver, 15e18);

        assertEq(uAsset.balanceOf(receiver), 25e18);
        assertEq(uAsset.totalSupply(), 25e18);
        assertEq(uAsset.checkMintableAmount(minter), 75e18);
    }

    function testOutboundRateLimitThroughProxy() external {
        vm.prank(owner);
        uAsset.setOutboundRateLimit(101, 10e18, 1 days);

        (, uint256 amountCanBeSent) = uAsset.getAmountCanBeSent(101);
        assertEq(amountCanBeSent, 10e18);
    }

    function testUnconfiguredPeerQuoteNotLocallyBlocked() external {
        SendParam memory sendParam = SendParam({
            dstEid: 101,
            to: bytes32(uint256(uint160(address(0xBEEF)))),
            amountLD: 1e18,
            minAmountLD: 0,
            extraOptions: bytes(""),
            composeMsg: bytes(""),
            oftCmd: bytes("")
        });

        (,, uint256 amountReceivedLD) = _quoteReceipt(sendParam);
        assertEq(amountReceivedLD, 1e18);
    }

    function _quoteReceipt(SendParam memory sendParam) internal view returns (uint256, uint256, uint256) {
        (,, OFTReceipt memory receipt) = uAsset.quoteOFT(sendParam);
        return (0, receipt.amountSentLD, receipt.amountReceivedLD);
    }

    function _quoteAmountReceived(uint256 amount) internal view returns (uint256) {
        SendParam memory sendParam = SendParam({
            dstEid: 101,
            to: bytes32(uint256(uint160(address(0xBEEF)))),
            amountLD: amount,
            minAmountLD: 0,
            extraOptions: bytes(""),
            composeMsg: bytes(""),
            oftCmd: bytes("")
        });

        (,, uint256 amountReceivedLD) = _quoteReceipt(sendParam);
        return amountReceivedLD;
    }
}
