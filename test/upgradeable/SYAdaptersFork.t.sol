// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {IAaveV3Pool} from "../../src/integrations/aave/interfaces/IAaveV3Pool.sol";
import {IAToken} from "../../src/integrations/aave/interfaces/IAToken.sol";
import {IAsBnbMinter} from "../../src/integrations/aster/interfaces/IAsBnbMinter.sol";
import {IListaBNBStakeManager} from "../../src/integrations/aster/interfaces/IListaBNBStakeManager.sol";
import {IYieldProxy} from "../../src/integrations/aster/interfaces/IYieldProxy.sol";
import {IListaStakeManager} from "../../src/integrations/lista/interfaces/IListaStakeManager.sol";
import {IWstETH} from "../../src/integrations/lido/interfaces/IWstETH.sol";
import {IWETH} from "../../src/libraries/IWETH.sol";
import {OutrunAaveV3SYUpgradeable} from "../../src/yield/adapters/aave/OutrunAaveV3SYUpgradeable.sol";
import {OutrunAsBNBSYUpgradeable} from "../../src/yield/adapters/aster/OutrunAsBNBSYUpgradeable.sol";
import {OutrunStakedUSDeSYUpgradeable} from "../../src/yield/adapters/ethena/OutrunStakedUSDeSYUpgradeable.sol";
import {OutrunSlisBNBSYUpgradeable} from "../../src/yield/adapters/lista/OutrunSlisBNBSYUpgradeable.sol";
import {OutrunWstETHSYUpgradeable} from "../../src/yield/adapters/lido/OutrunWstETHSYUpgradeable.sol";
import {OutrunStakedUsdsSYUpgradeable} from "../../src/yield/adapters/sky/OutrunStakedUsdsSYUpgradeable.sol";

contract SYAdaptersForkTest is Test {
    address internal constant OWNER = address(0xA11CE);
    uint256 internal constant BSC_MAINNET_CHAIN_ID = 56;

    // Current live Lista stake manager on BSC mainnet.
    address internal constant STAKE_MANAGER_PROXY = 0x1adB950d8bB3dA4bE104211D5AB038628e477fE6;
    address internal constant EXPECTED_SLIS_BNB = 0xB0b84D294e0C75A6abe60171b70edEb2EFd14A1B;

    // Current live Aster asBNB minter wiring on BSC mainnet.
    address internal constant AS_BNB = 0x77734e70b6E88b4d82fE632a168EDf6e700912b6;
    address internal constant AS_BNB_MINTER = 0x2F31ab8950c50080E77999fa456372f276952fD8;

    OutrunSlisBNBSYUpgradeable internal slisSy;
    OutrunAsBNBSYUpgradeable internal asBnbSy;
    address internal slisBnb;
    address internal asBnbYieldProxy;
    address internal asBnbStakeManager;

    function setUp() external {
        string memory bscRpc;
        try vm.envString("BSC_MAINNET_RPC") returns (string memory rpc) {
            bscRpc = rpc;
        } catch {
            vm.skip(true);
            return;
        }

        try vm.createSelectFork(bscRpc) returns (uint256) {}
        catch {
            vm.skip(true);
            return;
        }
        assertEq(block.chainid, BSC_MAINNET_CHAIN_ID);

        assertGt(STAKE_MANAGER_PROXY.code.length, 0);
        assertGt(AS_BNB.code.length, 0);
        assertGt(AS_BNB_MINTER.code.length, 0);

        slisSy = _deploySlisSy();
        slisBnb = slisSy.yieldBearingToken();
        asBnbYieldProxy = IAsBnbMinter(AS_BNB_MINTER).yieldProxy();
        asBnbStakeManager = IYieldProxy(asBnbYieldProxy).stakeManager();
        asBnbSy = _deployAsBnbSy();
    }

    function testFork_SlisBnbLiveWiringMatchesMainnetAddress() external {
        assertEq(slisBnb, EXPECTED_SLIS_BNB);
        assertEq(IAsBnbMinter(AS_BNB_MINTER).token(), EXPECTED_SLIS_BNB);
    }

    function testFork_SlisBnbExchangeRateMatchesOnchainQuote() external {
        uint256 expected = IListaStakeManager(STAKE_MANAGER_PROXY).convertSnBnbToBnb(1 ether);
        assertEq(slisSy.exchangeRate(), expected);
    }

    function testFork_SlisBnbPreviewDepositNativeMatchesOnchainQuote() external {
        uint256 amount = 1 ether;
        uint256 expected = IListaStakeManager(STAKE_MANAGER_PROXY).convertBnbToSnBnb(amount);
        assertEq(slisSy.previewDeposit(address(0), amount), expected);
    }

    function testFork_SlisBnbPreviewDepositMatchesActualDeposit() external {
        uint256 amount = 1 ether;
        uint256 previewShares = slisSy.previewDeposit(address(0), amount);

        vm.deal(address(this), amount);
        uint256 actualShares = slisSy.deposit{value: amount}(address(this), address(0), amount, 0);

        assertEq(previewShares, actualShares);
        assertEq(slisSy.balanceOf(address(this)), actualShares);
    }

    function testFork_AsBnbLiveWiringMatchesMainnetAddress() external {
        assertEq(IAsBnbMinter(AS_BNB_MINTER).asBnb(), AS_BNB);
        assertEq(IAsBnbMinter(AS_BNB_MINTER).token(), EXPECTED_SLIS_BNB);
        assertEq(asBnbYieldProxy, asBnbSy.YIELD_PROXY());
        assertEq(asBnbStakeManager, STAKE_MANAGER_PROXY);
        assertEq(asBnbSy.STAKE_MANAGER(), STAKE_MANAGER_PROXY);
    }

    function testFork_AsBnbExchangeRateMatchesTwoHopQuote() external {
        uint256 slisBnbPerShare = IAsBnbMinter(AS_BNB_MINTER).convertToTokens(1 ether);
        uint256 expectedRate = IListaBNBStakeManager(asBnbStakeManager).convertSnBnbToBnb(slisBnbPerShare);
        assertEq(asBnbSy.exchangeRate(), expectedRate);
    }

    function testFork_AsBnbPreviewDepositNativeMatchesTwoHopQuote() external {
        uint256 amount = 1 ether;
        uint256 slisQuote = IListaBNBStakeManager(asBnbStakeManager).convertBnbToSnBnb(amount);
        uint256 expectedShares = IAsBnbMinter(AS_BNB_MINTER).convertToAsBnb(slisQuote);
        assertEq(asBnbSy.previewDeposit(address(0), amount), expectedShares);
    }

    function testFork_AsBnbPreviewDepositMatchesActualDeposit() external {
        assertFalse(IYieldProxy(asBnbSy.YIELD_PROXY()).activitiesOnGoing());

        uint256 amount = 1 ether;
        uint256 previewShares = asBnbSy.previewDeposit(address(0), amount);

        vm.deal(address(this), amount);
        uint256 actualShares = asBnbSy.deposit{value: amount}(address(this), address(0), amount, 0);

        assertEq(actualShares, previewShares);
        assertEq(asBnbSy.balanceOf(address(this)), actualShares);
    }

    function _deploySlisSy() internal returns (OutrunSlisBNBSYUpgradeable) {
        OutrunSlisBNBSYUpgradeable impl = new OutrunSlisBNBSYUpgradeable();
        return OutrunSlisBNBSYUpgradeable(
            payable(address(
                    new ERC1967Proxy(
                        address(impl),
                        abi.encodeCall(
                            OutrunSlisBNBSYUpgradeable.initialize, (OWNER, EXPECTED_SLIS_BNB, STAKE_MANAGER_PROXY)
                        )
                    )
                ))
        );
    }

    function _deployAsBnbSy() internal returns (OutrunAsBNBSYUpgradeable) {
        OutrunAsBNBSYUpgradeable impl = new OutrunAsBNBSYUpgradeable();
        address slis = IAsBnbMinter(AS_BNB_MINTER).token();
        return OutrunAsBNBSYUpgradeable(
            payable(address(
                    new ERC1967Proxy(
                        address(impl),
                        abi.encodeCall(OutrunAsBNBSYUpgradeable.initialize, (OWNER, AS_BNB, slis, AS_BNB_MINTER))
                    )
                ))
        );
    }
}

contract SYAdaptersMainnetForkTest is Test {
    address internal constant OWNER = address(0xA11CE);
    uint256 internal constant ETHEREUM_MAINNET_CHAIN_ID = 1;

    address internal constant AAVE_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    address internal constant A_WETH = 0x4d5F47FA6A74757f35C14fD3a6Ef8E3C9BC514E8;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address internal constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address internal constant USDE = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
    address internal constant SUSDE = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
    address internal constant USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;
    address internal constant SUSDS = 0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD;

    OutrunAaveV3SYUpgradeable internal aaveSy;
    OutrunWstETHSYUpgradeable internal lidoSy;
    OutrunStakedUSDeSYUpgradeable internal ethenaSy;
    OutrunStakedUsdsSYUpgradeable internal skySy;

    function setUp() external {
        string memory mainnetRpc;
        try vm.envString("ETHEREUM_MAINNET_RPC") returns (string memory rpc) {
            mainnetRpc = rpc;
        } catch {
            vm.skip(true);
            return;
        }

        vm.createSelectFork(mainnetRpc);
        assertEq(block.chainid, ETHEREUM_MAINNET_CHAIN_ID);

        assertGt(AAVE_POOL.code.length, 0);
        assertGt(A_WETH.code.length, 0);
        assertGt(WETH.code.length, 0);
        assertGt(STETH.code.length, 0);
        assertGt(WSTETH.code.length, 0);
        assertGt(USDE.code.length, 0);
        assertGt(SUSDE.code.length, 0);
        assertGt(USDS.code.length, 0);
        assertGt(SUSDS.code.length, 0);

        aaveSy = _deployAaveSy();
        lidoSy = _deployLidoSy();
        ethenaSy = _deployEthenaSy();
        skySy = _deploySkySy();
    }

    function testMainnetFork_AaveWethDepositMatchesLiveAave() external {
        uint256 amount = 0.1 ether;
        uint256 wethBefore = IERC20(WETH).balanceOf(address(this));
        vm.deal(address(this), amount);
        IWETH(WETH).deposit{value: amount}();
        IERC20(WETH).approve(address(aaveSy), amount);

        assertEq(aaveSy.yieldBearingToken(), A_WETH);
        assertEq(aaveSy.underlying(), WETH);
        assertEq(aaveSy.aavePool(), AAVE_POOL);
        assertEq(IAToken(A_WETH).UNDERLYING_ASSET_ADDRESS(), WETH);
        assertEq(aaveSy.exchangeRate(), IAaveV3Pool(AAVE_POOL).getReserveNormalizedIncome(WETH) / 1e9);

        uint256 scaledBefore = IAToken(A_WETH).scaledBalanceOf(address(aaveSy));
        uint256 previewShares = aaveSy.previewDeposit(WETH, amount);
        uint256 shares = aaveSy.deposit(address(this), WETH, amount, 0);
        uint256 scaledAfter = IAToken(A_WETH).scaledBalanceOf(address(aaveSy));
        assertApproxEqAbs(shares, previewShares, 1);
        assertEq(shares, scaledAfter - scaledBefore);
        assertEq(aaveSy.balanceOf(address(this)), shares);
        assertApproxEqAbs(IERC20(A_WETH).balanceOf(address(aaveSy)), amount, 2);

        uint256 previewRedeem = aaveSy.previewRedeem(WETH, shares);
        uint256 redeemed = aaveSy.redeem(address(this), shares, WETH, 0, false);
        assertEq(redeemed, previewRedeem);
        assertEq(aaveSy.balanceOf(address(this)), 0);
        assertEq(IAToken(A_WETH).scaledBalanceOf(address(aaveSy)), scaledBefore);
        assertEq(IERC20(WETH).balanceOf(address(this)) - wethBefore, redeemed);
    }

    function testMainnetFork_LidoNativeDepositAndRedeemToStEthMatchesLiveLido() external {
        uint256 amount = 0.1 ether;
        vm.deal(address(this), amount);

        assertEq(lidoSy.yieldBearingToken(), WSTETH);
        assertEq(lidoSy.STETH(), STETH);
        assertEq(lidoSy.exchangeRate(), IWstETH(WSTETH).stEthPerToken());

        uint256 previewShares = lidoSy.previewDeposit(address(0), amount);
        uint256 shares = lidoSy.deposit{value: amount}(address(this), address(0), amount, 0);
        assertApproxEqAbs(shares, previewShares, 1);
        assertEq(lidoSy.balanceOf(address(this)), shares);

        uint256 previewStEth = lidoSy.previewRedeem(STETH, shares);
        uint256 redeemed = lidoSy.redeem(address(this), shares, STETH, 0, false);
        assertApproxEqAbs(redeemed, previewStEth, 1);
        assertEq(lidoSy.balanceOf(address(this)), 0);
        assertApproxEqAbs(IERC20(STETH).balanceOf(address(this)), redeemed, 1);
    }

    function testMainnetFork_EthenaUSDeDepositMatchesLiveVault() external {
        uint256 amount = 100 ether;
        deal(USDE, address(this), amount);
        IERC20(USDE).approve(address(ethenaSy), amount);

        assertEq(ethenaSy.yieldBearingToken(), SUSDE);
        assertEq(ethenaSy.USDE(), USDE);
        assertEq(IERC4626(SUSDE).asset(), USDE);
        assertEq(ethenaSy.exchangeRate(), IERC4626(SUSDE).convertToAssets(1 ether));

        uint256 previewShares = ethenaSy.previewDeposit(USDE, amount);
        uint256 shares = ethenaSy.deposit(address(this), USDE, amount, 0);
        assertEq(shares, previewShares);
        assertEq(ethenaSy.balanceOf(address(this)), shares);
        assertEq(IERC20(SUSDE).balanceOf(address(ethenaSy)), shares);
    }

    function testMainnetFork_SkyUSDSDepositAndRedeemMatchesLiveVault() external {
        uint256 amount = 100 ether;
        deal(USDS, address(this), amount);
        IERC20(USDS).approve(address(skySy), amount);

        assertEq(skySy.yieldBearingToken(), SUSDS);
        assertEq(skySy.USDS(), USDS);
        assertEq(IERC4626(SUSDS).asset(), USDS);
        assertEq(skySy.exchangeRate(), IERC4626(SUSDS).convertToAssets(1 ether));

        uint256 previewShares = skySy.previewDeposit(USDS, amount);
        uint256 shares = skySy.deposit(address(this), USDS, amount, 0);
        assertEq(shares, previewShares);
        assertEq(skySy.balanceOf(address(this)), shares);
        assertEq(IERC20(SUSDS).balanceOf(address(skySy)), shares);

        uint256 previewAssets = skySy.previewRedeem(USDS, shares);
        uint256 redeemed = skySy.redeem(address(this), shares, USDS, 0, false);
        assertEq(redeemed, previewAssets);
        assertEq(skySy.balanceOf(address(this)), 0);
        assertEq(IERC20(USDS).balanceOf(address(this)), redeemed);
    }

    function _deployAaveSy() internal returns (OutrunAaveV3SYUpgradeable) {
        OutrunAaveV3SYUpgradeable impl = new OutrunAaveV3SYUpgradeable();
        return OutrunAaveV3SYUpgradeable(
            payable(address(
                    new ERC1967Proxy(
                        address(impl),
                        abi.encodeCall(
                            OutrunAaveV3SYUpgradeable.initialize, ("SY Aave WETH", "SY aWETH", A_WETH, AAVE_POOL, OWNER)
                        )
                    )
                ))
        );
    }

    function _deployLidoSy() internal returns (OutrunWstETHSYUpgradeable) {
        OutrunWstETHSYUpgradeable impl = new OutrunWstETHSYUpgradeable();
        return OutrunWstETHSYUpgradeable(
            payable(address(
                    new ERC1967Proxy(
                        address(impl), abi.encodeCall(OutrunWstETHSYUpgradeable.initialize, (OWNER, STETH, WSTETH))
                    )
                ))
        );
    }

    function _deployEthenaSy() internal returns (OutrunStakedUSDeSYUpgradeable) {
        OutrunStakedUSDeSYUpgradeable impl = new OutrunStakedUSDeSYUpgradeable();
        return OutrunStakedUSDeSYUpgradeable(
            payable(address(
                    new ERC1967Proxy(
                        address(impl), abi.encodeCall(OutrunStakedUSDeSYUpgradeable.initialize, (OWNER, USDE, SUSDE))
                    )
                ))
        );
    }

    function _deploySkySy() internal returns (OutrunStakedUsdsSYUpgradeable) {
        OutrunStakedUsdsSYUpgradeable impl = new OutrunStakedUsdsSYUpgradeable();
        return OutrunStakedUsdsSYUpgradeable(
            payable(address(
                    new ERC1967Proxy(
                        address(impl), abi.encodeCall(OutrunStakedUsdsSYUpgradeable.initialize, (OWNER, USDS, SUSDS))
                    )
                ))
        );
    }
}
