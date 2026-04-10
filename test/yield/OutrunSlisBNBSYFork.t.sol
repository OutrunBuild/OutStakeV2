// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {IListaStakeManager} from "../../src/integrations/lista/interfaces/IListaStakeManager.sol";
import {OutrunSlisBNBSY} from "../../src/yield/adapters/lista/OutrunSlisBNBSY.sol";

contract OutrunSlisBNBSYForkTest is Test {
    address internal constant OWNER = address(0xA11CE);
    // Pinned to the current live Lista stake manager on BSC mainnet.
    address internal constant STAKE_MANAGER_PROXY = 0x1adB950d8bB3dA4bE104211D5AB038628e477fE6;
    address internal constant EXPECTED_SLIS_BNB = 0xB0b84D294e0C75A6abe60171b70edEb2EFd14A1B;

    OutrunSlisBNBSY internal sy;

    function setUp() external {
        vm.createSelectFork(vm.rpcUrl("bsc_mainnet"));

        sy = new OutrunSlisBNBSY(OWNER, EXPECTED_SLIS_BNB, STAKE_MANAGER_PROXY);
    }

    function testFork_ExchangeRateMatchesOnchainQuote() external {
        uint256 expected = IListaStakeManager(STAKE_MANAGER_PROXY).convertSnBnbToBnb(1 ether);

        assertEq(sy.exchangeRate(), expected);
    }

    function testFork_ExchangeRateGTEOne() external {
        assertGe(sy.exchangeRate(), 1 ether);
    }

    function testFork_PreviewDepositNativeMatchesConvertQuote() external {
        uint256 amount = 1 ether;
        uint256 expected = IListaStakeManager(STAKE_MANAGER_PROXY).convertBnbToSnBnb(amount);

        assertEq(sy.previewDeposit(address(0), amount), expected);
    }

    function testFork_GetTotalPooledBnbIsNonZero() external {
        assertGt(IListaStakeManager(STAKE_MANAGER_PROXY).getTotalPooledBnb(), 0);
    }

    function testFork_PreviewDepositMatchesActualDeposit() external {
        uint256 amount = 1 ether;

        // 获取 preview 报价
        uint256 previewShares = sy.previewDeposit(address(0), amount);

        // 执行实际 deposit
        vm.deal(address(this), amount);
        uint256 actualShares = sy.deposit{value: amount}(address(this), address(0), amount, 0);

        // preview 和 actual 应该相等（同一区块，状态不变）
        assertEq(previewShares, actualShares);
    }
}
