// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";

import {OutrunUniversalAssets} from "../../src/assets/base/OutrunUniversalAssets.sol";
import {IUniversalAssets} from "../../src/assets/interfaces/IUniversalAssets.sol";
import {MockLzEndpoint} from "./helpers/OFTTestHelper.sol";

contract OutrunUniversalAssetsTest is Test {
    OutrunUniversalAssets internal uAsset;
    MockLzEndpoint internal endpoint;

    address internal owner = address(0xA11CE);
    address internal minter = address(0xB0B);
    address internal receiver = address(0xCAFE);

    function setUp() external {
        endpoint = new MockLzEndpoint();
        uAsset = new OutrunUniversalAssets("Outrun UAsset", "UAsset", 18, address(endpoint), owner);

        vm.prank(owner);
        uAsset.setPeer(101, bytes32(uint256(uint160(address(0xBEEF)))));
    }

    function testSetMintingCapControlsMintability() external {
        vm.prank(owner);
        uAsset.setMintingCap(minter, 100e18);

        assertEq(uAsset.checkMintableAmount(minter), 100e18);

        vm.prank(minter);
        uAsset.mint(receiver, 40e18);

        assertEq(uAsset.checkMintableAmount(minter), 60e18);
        assertEq(uAsset.balanceOf(receiver), 40e18);
    }

    function testRevokeMinterStopsFurtherMinting() external {
        vm.prank(owner);
        uAsset.setMintingCap(minter, 100e18);

        vm.prank(minter);
        uAsset.mint(receiver, 40e18);

        vm.prank(owner);
        uAsset.revokeMinter(minter);

        assertEq(uAsset.checkMintableAmount(minter), 0);

        vm.prank(minter);
        vm.expectRevert(IUniversalAssets.ReachMintCap.selector);
        uAsset.mint(receiver, 1);
    }

    function testRepayBurnsBalanceAndRestoresMintHeadroom() external {
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

    function testSingleArgumentBurnEntryPointIsRemoved() external {
        vm.prank(owner);
        uAsset.setMintingCap(minter, 100e18);

        vm.prank(minter);
        uAsset.mint(receiver, 10e18);

        vm.prank(receiver);
        // solhint-disable-next-line avoid-low-level-calls
        (bool ok,) = address(uAsset).call(abi.encodeWithSignature("burn(uint256)", 1e18));

        assertFalse(ok);
        assertEq(uAsset.balanceOf(receiver), 10e18);
        assertEq(uAsset.totalSupply(), 10e18);
        assertEq(uAsset.checkMintableAmount(minter), 90e18);
    }

    function testQuoteSendRevertsWhenAmountSDOverflows() external {
        endpoint.setQuoteNativeFee(0.1 ether);

        uint256 overflowAmountLD = (uint256(type(uint64).max) + 1) * uAsset.decimalConversionRate();
        SendParam memory sendParam = SendParam({
            dstEid: 101,
            to: bytes32(uint256(uint160(address(0xBEEF)))),
            amountLD: overflowAmountLD,
            minAmountLD: 0,
            extraOptions: bytes("opts"),
            composeMsg: bytes(""),
            oftCmd: bytes("")
        });

        vm.expectRevert(abi.encodeWithSignature("AmountSDOverflowed(uint256)", (uint256(type(uint64).max) + 1)));
        uAsset.quoteSend(sendParam, false);
    }
}
