// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {BaseScript} from "../lib/BaseScript.s.sol";
import {OutrunStakingPosition} from "../../src/position/OutrunStakingPosition.sol";
import {IUniversalAssets} from "../../src/assets/interfaces/IUniversalAssets.sol";

import {OutrunWstETHSY} from "../../src/yield/adapters/lido/OutrunWstETHSY.sol";
import {OutrunAaveV3SY} from "../../src/yield/adapters/aave/OutrunAaveV3SY.sol";
import {OutrunStakedUSDeSY} from "../../src/yield/adapters/ethena/OutrunStakedUSDeSY.sol";

contract YieldDeployScript is BaseScript {
    address internal UETH;
    address internal UUSD;
    address internal UBNB;

    address internal owner;
    address internal revenuePool;
    address internal keeper;

    function run() public broadcaster {
        UETH = vm.envAddress("UETH");
        UUSD = vm.envAddress("UUSD");
        UBNB = vm.envAddress("UBNB");
        owner = vm.envAddress("OWNER");
        revenuePool = vm.envAddress("REVENUE_POOL");
        keeper = vm.envAddress("KEEPER");

        // 20000 runs
        // _supportWstETHOnSepolia();
        // _supportSUSDeOnSepolia();
        _supportAUSDC();
    }

    /**
     * Support wstETH (Sepolia)
     */
    function _supportWstETHOnSepolia() internal {
        if (block.chainid != vm.envUint("ETHEREUM_SEPOLIA_CHAINID")) return;

        address stETH = vm.envAddress("SEPOLIA_STETH");
        address wstETH = vm.envAddress("SEPOLIA_WSTETH");

        // SY
        OutrunWstETHSY SY_wstETH = new OutrunWstETHSY(owner, stETH, wstETH);
        address wstETHSYAddress = address(SY_wstETH);

        // Position
        OutrunStakingPosition SP_wstETH = new OutrunStakingPosition(owner, 0, revenuePool, wstETHSYAddress, UETH);
        address wstETHSPAddress = address(SP_wstETH);

        SP_wstETH.setKeeper(keeper);
        IUniversalAssets(UETH).setMintingCap(wstETHSPAddress, 1000000000 ether);
    }

    /**
     * Support sUSDe (Sepolia)
     */
    function _supportSUSDeOnSepolia() internal {
        if (block.chainid != vm.envUint("ETHEREUM_SEPOLIA_CHAINID")) return;

        address USDe = vm.envAddress("SEPOLIA_USDE");
        address sUSDe = vm.envAddress("SEPOLIA_SUSDE");

        // SY
        OutrunStakedUSDeSY SY_sUSDe = new OutrunStakedUSDeSY(owner, USDe, sUSDe);
        address sUSDeSYAddress = address(SY_sUSDe);

        // Position
        OutrunStakingPosition SP_sUSDe = new OutrunStakingPosition(owner, 0, revenuePool, sUSDeSYAddress, UUSD);
        address sUSDeSPAddress = address(SP_sUSDe);

        SP_sUSDe.setKeeper(keeper);
        IUniversalAssets(UUSD).setMintingCap(sUSDeSPAddress, 1000000000 ether);
    }

    /**
     * Support aUSDC (Arbitrum Sepolia, Base Sepolia)
     */
    function _supportAUSDC() internal {
        address aUSDC;
        address aavePool;
        if (block.chainid == vm.envUint("ARBITRUM_SEPOLIA_CHAINID")) {
            aUSDC = vm.envAddress("ARBITRUM_SEPOLIA_AUSDC");
            aavePool = vm.envAddress("ARBITRUM_SEPOLIA_POOL");
        } else if (block.chainid == vm.envUint("BASE_SEPOLIA_CHAINID")) {
            aUSDC = vm.envAddress("BASE_SEPOLIA_AUSDC");
            aavePool = vm.envAddress("BASE_SEPOLIA_POOL");
        } else {
            return;
        }

        // SY
        OutrunAaveV3SY SY_aUSDC = new OutrunAaveV3SY("SY AaveE aUSDC", "SY aUSDC", aUSDC, aavePool, owner);
        address aUSDCSYAddress = address(SY_aUSDC);

        // Position
        OutrunStakingPosition SP_aUSDC = new OutrunStakingPosition(owner, 0, revenuePool, aUSDCSYAddress, UUSD);
        address aUSDCSPAddress = address(SP_aUSDC);

        SP_aUSDC.setKeeper(keeper);
        IUniversalAssets(UUSD).setMintingCap(aUSDCSPAddress, 1000000000 ether);
    }
}
