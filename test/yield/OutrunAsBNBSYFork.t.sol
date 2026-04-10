// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {IAsBnbMinter} from "../../src/integrations/aster/interfaces/IAsBnbMinter.sol";
import {IListaBNBStakeManager} from "../../src/integrations/aster/interfaces/IListaBNBStakeManager.sol";
import {OutrunAsBNBSY} from "../../src/yield/adapters/aster/OutrunAsBNBSY.sol";

contract OutrunAsBNBSYForkTest is Test {
    address internal constant OWNER = address(0xA11CE);
    address internal constant AS_BNB = 0x77734e70b6E88b4d82fE632a168EDf6e700912b6;
    address internal constant AS_BNB_MINTER = 0x2F31ab8950c50080E77999fa456372f276952fD8;
    address internal constant EXPECTED_SLIS_BNB = 0xB0b84D294e0C75A6abe60171b70edEb2EFd14A1B;

    OutrunAsBNBSY internal sy;
    address internal slisBnb;

    function setUp() external {
        vm.createSelectFork(vm.rpcUrl("bsc_mainnet"));

        slisBnb = IAsBnbMinter(AS_BNB_MINTER).token();
        sy = new OutrunAsBNBSY(OWNER, AS_BNB, slisBnb, AS_BNB_MINTER);
    }

    function testFork_SlisBnbLiveWiringMatchesPinnedMainnetAddress() external {
        assertEq(slisBnb, EXPECTED_SLIS_BNB);
    }

    function testFork_ExchangeRateMatchesMinter() external {
        uint256 slisBnbPerShare = IAsBnbMinter(AS_BNB_MINTER).convertToTokens(1 ether);
        uint256 expectedRate = IListaBNBStakeManager(sy.STAKE_MANAGER()).convertSnBnbToBnb(slisBnbPerShare);

        assertEq(sy.exchangeRate(), expectedRate);
    }

    function testFork_PreviewDepositNativeMatchesTwoHopQuote() external {
        uint256 amount = 1 ether;
        uint256 slisQuote = IListaBNBStakeManager(sy.STAKE_MANAGER()).convertBnbToSnBnb(amount);
        uint256 expectedShares = IAsBnbMinter(AS_BNB_MINTER).convertToAsBnb(slisQuote);

        assertEq(sy.previewDeposit(address(0), amount), expectedShares);
    }
}
