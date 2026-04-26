// SPDX-License-Identifier: UNLICENSED
// solhint-disable no-console,check-send-result
pragma solidity ^0.8.28;

import {IOAppCore} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppCore.sol";
import {ILayerZeroEndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {IOFT, SendParam, MessagingFee} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";

import {BaseScript} from "../lib/BaseScript.s.sol";
import {console} from "forge-std/console.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {OutrunRouter} from "../../src/router/OutrunRouter.sol";
import {IOutrunRouter} from "../../src/router/interfaces/IOutrunRouter.sol";
import {IOutrunDeployer} from "./deployment/interfaces/IOutrunDeployer.sol";
import {OutrunDeployer} from "./deployment/OutrunDeployer.sol";
import {IOutrunStakeManager} from "../../src/position/interfaces/IOutrunStakeManager.sol";
import {OutrunStakingPosition} from "../../src/position/OutrunStakingPosition.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {OutrunOFT} from "../../src/assets/omnichain/OutrunOFT.sol";
import {OutrunUniversalAssets} from "../../src/assets/base/OutrunUniversalAssets.sol";
import {IUniversalAssets} from "../../src/assets/interfaces/IUniversalAssets.sol";
import {IStandardizedYield} from "../../src/yield/interfaces/IStandardizedYield.sol";

import {Faucet, IFaucet} from "../../test/support/Faucet.sol";
import {MockUSDC} from "../../test/support/MockUSDC.sol";
import {MockAUSDC} from "../../test/support/MockAUSDC.sol";
import {MockSUSDS} from "../../test/support/MockSUSDS.sol";
import {MockAUSDCOracle} from "../../test/support/MockAUSDCOracle.sol";
import {MockSUSDSOracle} from "../../test/support/MockSUSDSOracle.sol";
import {MockOutrunAUSDCSY} from "../../test/yield/MockOutrunAUSDCSY.sol";
import {MockOutrunSUSDSSY} from "../../test/yield/MockOutrunSUSDSSY.sol";

interface IOwnable {
    function owner() external view returns (address);
}

contract OutstakeScript is BaseScript {
    using OptionsBuilder for bytes;
    using SafeCast for uint256;

    error InvalidEndpoint();
    error InvalidOmnichainId();
    error InvalidOmnichainConfig();
    error InvalidOutboundRateLimit();
    error InvalidOutboundRateWindow();
    error InvalidOwner();
    error InvalidKeeper();
    error InvalidAddress();

    address internal ueth;
    address internal uusd;
    address internal ubnb;

    address internal owner;
    address internal keeper;
    address internal revenuePool;
    address internal outrunDeployer;
    address internal outrunRouter;
    address internal memeverseLauncher;

    mapping(uint32 chainId => address) public endpoints;
    mapping(uint32 chainId => uint32) public endpointIds;

    function run() public broadcaster {
        ueth = vm.envAddress("UETH");
        uusd = vm.envAddress("UUSD");
        ubnb = vm.envAddress("UBNB");
        owner = vm.envAddress("OWNER");
        keeper = vm.envAddress("KEEPER");
        revenuePool = vm.envAddress("REVENUE_POOL");
        outrunDeployer = vm.envAddress("OUTRUN_DEPLOYER");
        outrunRouter = vm.envAddress("OUTRUN_ROUTER");
        memeverseLauncher = vm.envAddress("MEMEVERSE_LAUNCHER");

        // _deployOutrunDeployer(1);

        _chainsInit();
        // _crossChainOFT();
        // _deployUETH(1);
        // _deployUUSD(1);
        // _deployUBNB(1);
        _deployOutrunRouter(7);
        // _updateRouterLauncher();
        // _deployMockERC20(1);
        // _deployMockOracle(1);
        // _deployMockERC20SY(1);
        // _supportMockAUSDC(13);   // 20000 runs
        // _supportMockSUSDS(13);   // 20000 runs
    }

    function _deployOutrunDeployer(uint256 nonce) internal {
        bytes32 salt = keccak256(abi.encodePacked(owner, "OutrunDeployer", nonce));
        address outrunDeployerAddr =
            Create2.deploy(0, salt, abi.encodePacked(type(OutrunDeployer).creationCode, abi.encode(owner)));

        console.log("OutrunDeployer deployed on %s", outrunDeployerAddr);
    }

    function _chainsInit() internal {
        endpoints[97] = vm.envAddress("BSC_TESTNET_ENDPOINT");
        endpoints[84532] = vm.envAddress("BASE_SEPOLIA_ENDPOINT");
        endpoints[421614] = vm.envAddress("ARBITRUM_SEPOLIA_ENDPOINT");
        endpoints[43113] = vm.envAddress("AVALANCHE_FUJI_ENDPOINT");
        endpoints[80002] = vm.envAddress("POLYGON_AMOY_ENDPOINT");
        endpoints[57054] = vm.envAddress("SONIC_TESTNET_ENDPOINT");
        endpoints[11155420] = vm.envAddress("OPTIMISTIC_SEPOLIA_ENDPOINT");
        endpoints[300] = vm.envAddress("ZKSYNC_SEPOLIA_ENDPOINT");
        endpoints[59141] = vm.envAddress("LINEA_SEPOLIA_ENDPOINT");
        endpoints[168587773] = vm.envAddress("BLAST_SEPOLIA_ENDPOINT");
        endpoints[534351] = vm.envAddress("SCROLL_SEPOLIA_ENDPOINT");
        endpoints[10143] = vm.envAddress("MONAD_TESTNET_ENDPOINT");
        endpoints[80069] = vm.envAddress("BERA_SEPOLIA_ENDPOINT");
        endpoints[11155111] = vm.envAddress("ETHEREUM_SEPOLIA_ENDPOINT");

        endpointIds[97] = vm.envUint("BSC_TESTNET_EID").toUint32();
        endpointIds[84532] = vm.envUint("BASE_SEPOLIA_EID").toUint32();
        endpointIds[421614] = vm.envUint("ARBITRUM_SEPOLIA_EID").toUint32();
        endpointIds[43113] = vm.envUint("AVALANCHE_FUJI_EID").toUint32();
        endpointIds[80002] = vm.envUint("POLYGON_AMOY_EID").toUint32();
        endpointIds[57054] = vm.envUint("SONIC_TESTNET_EID").toUint32();
        endpointIds[11155420] = vm.envUint("OPTIMISTIC_SEPOLIA_EID").toUint32();
        endpointIds[300] = vm.envUint("ZKSYNC_SEPOLIA_EID").toUint32();
        endpointIds[59141] = vm.envUint("LINEA_SEPOLIA_EID").toUint32();
        endpointIds[168587773] = vm.envUint("BLAST_SEPOLIA_EID").toUint32();
        endpointIds[534351] = vm.envUint("SCROLL_SEPOLIA_EID").toUint32();
        endpointIds[10143] = vm.envUint("MONAD_TESTNET_EID").toUint32();
        endpointIds[80069] = vm.envUint("BERA_SEPOLIA_EID").toUint32();
        endpointIds[11155111] = vm.envUint("ETHEREUM_SEPOLIA_EID").toUint32();
    }

    function _deployUETH(uint256 nonce) internal {
        uint32[] memory omnichainIds = new uint32[](9);
        omnichainIds[0] = 97; // BSC Testnet
        omnichainIds[1] = 84532; // Base Sepolia
        omnichainIds[2] = 421614; // Arbitrum Sepolia
        omnichainIds[3] = 43113; // Avalanche Fuji C-Chain
        omnichainIds[4] = 80002; // Polygon Amoy
        omnichainIds[5] = 57054; // Sonic Blaze
        omnichainIds[6] = 168587773; // Blast Sepolia
        omnichainIds[7] = 534351; // Scroll Sepolia
        omnichainIds[8] = 11155111; // Sepolia
        // omnichainIds[9] = 10143;     // Monad Testnet
        // omnichainIds[10] = 80069;    // Bera Sepolia
        // omnichainIds[11] = 59141;    // Linea Sepolia
        // omnichainIds[12] = 11155420; // Optimistic Sepolia
        // omnichainIds[13] = 300;      // ZKsync Sepolia

        (uint192 outboundRateLimit, uint64 outboundRateWindow) =
            _outboundRateLimitConfig("UETH_OUTBOUND_RATE_LIMIT", "UETH_OUTBOUND_RATE_WINDOW_SECONDS");
        _validateUAssetDeploymentConfig(omnichainIds);

        bytes memory encodedArgs =
            abi.encode("Omnichain Universal Assets ETH", "UETH", 18, endpoints[uint32(block.chainid)], owner);
        bytes memory creationCode = abi.encodePacked(type(OutrunUniversalAssets).creationCode, encodedArgs);
        bytes32 salt = keccak256(abi.encodePacked("OmnichainUniversalAssetsETH", nonce));

        address UETH = IOutrunDeployer(outrunDeployer).deploy(salt, creationCode);
        bytes32 peer = bytes32(uint256(uint160(UETH)));

        _configureUAssetOmnichain(UETH, peer, omnichainIds, outboundRateLimit, outboundRateWindow);

        console.log("UETH deployed on %s", UETH);
    }

    function _deployUUSD(uint256 nonce) internal {
        uint32[] memory omnichainIds = new uint32[](9);
        omnichainIds[0] = 97; // BSC Testnet
        omnichainIds[1] = 84532; // Base Sepolia
        omnichainIds[2] = 421614; // Arbitrum Sepolia
        omnichainIds[3] = 43113; // Avalanche Fuji C-Chain
        omnichainIds[4] = 80002; // Polygon Amoy
        omnichainIds[5] = 57054; // Sonic Blaze
        omnichainIds[6] = 168587773; // Blast Sepolia
        omnichainIds[7] = 534351; // Scroll Sepolia
        omnichainIds[8] = 11155111; // Sepolia
        // omnichainIds[9] = 10143;     // Monad Testnet
        // omnichainIds[10] = 80069;    // Bera Sepolia
        // omnichainIds[11] = 59141;    // Linea Sepolia
        // omnichainIds[12] = 11155420; // Optimistic Sepolia
        // omnichainIds[13] = 300;      // ZKsync Sepolia

        (uint192 outboundRateLimit, uint64 outboundRateWindow) =
            _outboundRateLimitConfig("UUSD_OUTBOUND_RATE_LIMIT", "UUSD_OUTBOUND_RATE_WINDOW_SECONDS");
        _validateUAssetDeploymentConfig(omnichainIds);

        bytes memory encodedArgs =
            abi.encode("Omnichain Universal Assets USD", "UUSD", 18, endpoints[uint32(block.chainid)], owner);
        bytes memory creationCode = abi.encodePacked(type(OutrunUniversalAssets).creationCode, encodedArgs);
        bytes32 salt = keccak256(abi.encodePacked("OmnichainUniversalAssetsUSD", nonce));

        address UUSD = IOutrunDeployer(outrunDeployer).deploy(salt, creationCode);
        bytes32 peer = bytes32(uint256(uint160(UUSD)));

        _configureUAssetOmnichain(UUSD, peer, omnichainIds, outboundRateLimit, outboundRateWindow);

        console.log("UUSD deployed on %s", UUSD);
    }

    function _deployUBNB(uint256 nonce) internal {
        uint32[] memory omnichainIds = new uint32[](9);
        omnichainIds[0] = 97; // BSC Testnet
        omnichainIds[1] = 84532; // Base Sepolia
        omnichainIds[2] = 421614; // Arbitrum Sepolia
        omnichainIds[3] = 43113; // Avalanche Fuji C-Chain
        omnichainIds[4] = 80002; // Polygon Amoy
        omnichainIds[5] = 57054; // Sonic Blaze
        omnichainIds[6] = 168587773; // Blast Sepolia
        omnichainIds[7] = 534351; // Scroll Sepolia
        omnichainIds[8] = 11155111; // Sepolia
        // omnichainIds[9] = 10143;     // Monad Testnet
        // omnichainIds[10] = 80069;    // Bera Sepolia
        // omnichainIds[11] = 59141;    // Linea Sepolia
        // omnichainIds[12] = 11155420; // Optimistic Sepolia
        // omnichainIds[13] = 300;      // ZKsync Sepolia

        (uint192 outboundRateLimit, uint64 outboundRateWindow) =
            _outboundRateLimitConfig("UBNB_OUTBOUND_RATE_LIMIT", "UBNB_OUTBOUND_RATE_WINDOW_SECONDS");
        _validateUAssetDeploymentConfig(omnichainIds);

        bytes memory encodedArgs =
            abi.encode("Omnichain Universal Assets BNB", "UBNB", 18, endpoints[uint32(block.chainid)], owner);
        bytes memory creationCode = abi.encodePacked(type(OutrunUniversalAssets).creationCode, encodedArgs);
        bytes32 salt = keccak256(abi.encodePacked("OmnichainUniversalAssetsBNB", nonce));

        address UBNB = IOutrunDeployer(outrunDeployer).deploy(salt, creationCode);
        bytes32 peer = bytes32(uint256(uint160(UBNB)));

        _configureUAssetOmnichain(UBNB, peer, omnichainIds, outboundRateLimit, outboundRateWindow);

        console.log("UBNB deployed on %s", UBNB);
    }

    function _outboundRateLimitConfig(string memory limitEnv, string memory windowEnv)
        internal
        view
        returns (uint192 limit, uint64 window)
    {
        (uint256 rawLimit, uint256 rawWindow) = _rawOutboundRateLimitConfig(limitEnv, windowEnv);
        if (rawLimit == 0) revert InvalidOutboundRateLimit();
        if (rawWindow == 0) revert InvalidOutboundRateWindow();

        limit = rawLimit.toUint192();
        window = rawWindow.toUint64();
    }

    function _rawOutboundRateLimitConfig(string memory limitEnv, string memory windowEnv)
        internal
        view
        virtual
        returns (uint256 limit, uint256 window)
    {
        limit = vm.envUint(limitEnv);
        window = vm.envUint(windowEnv);
    }

    function _validateUAssetDeploymentConfig(uint32[] memory omnichainIds) internal view {
        if (owner != deployer) revert InvalidOwner();
        address localEndpoint = endpoints[uint32(block.chainid)];
        uint32 localEndpointId = endpointIds[uint32(block.chainid)];
        if (localEndpoint == address(0) || localEndpoint.code.length == 0 || localEndpointId == 0) {
            revert InvalidEndpoint();
        }

        try ILayerZeroEndpointV2(localEndpoint).eid() returns (uint32 eid) {
            if (eid != localEndpointId) revert InvalidEndpoint();
        } catch {
            revert InvalidEndpoint();
        }

        for (uint256 i; i < omnichainIds.length; ++i) {
            uint32 omnichainId = omnichainIds[i];
            if (omnichainId == block.chainid) continue;
            if (endpointIds[omnichainId] == 0) revert InvalidOmnichainId();
        }
    }

    function _configureUAssetOmnichain(
        address uAsset,
        bytes32 peer,
        uint32[] memory omnichainIds,
        uint192 outboundRateLimit,
        uint64 outboundRateWindow
    ) internal {
        for (uint256 i; i < omnichainIds.length; ++i) {
            uint32 omnichainId = omnichainIds[i];
            if (omnichainId == block.chainid) continue;

            uint32 endpointId = endpointIds[omnichainId];
            OutrunOFT(uAsset).setOutboundRateLimit(endpointId, outboundRateLimit, outboundRateWindow);
            IOAppCore(uAsset).setPeer(endpointId, peer);
            _assertUAssetOmnichainConfig(uAsset, endpointId, peer, outboundRateLimit, outboundRateWindow);
        }
    }

    function _assertUAssetOmnichainConfig(
        address uAsset,
        uint32 endpointId,
        bytes32 peer,
        uint192 outboundRateLimit,
        uint64 outboundRateWindow
    ) internal view {
        if (IOAppCore(uAsset).peers(endpointId) != peer) revert InvalidOmnichainConfig();

        (,, uint256 limit, uint256 window) = OutrunOFT(uAsset).rateLimits(endpointId);
        if (limit != outboundRateLimit || window != outboundRateWindow) revert InvalidOmnichainConfig();
    }

    function _deployMockERC20(uint256 nonce) internal {
        if (owner != deployer) revert InvalidOwner();

        bytes32 salt = keccak256(abi.encodePacked("Faucet", nonce));
        bytes memory creationCode = abi.encodePacked(type(Faucet).creationCode, abi.encode(owner));
        address faucetAddr = IOutrunDeployer(outrunDeployer).deploy(salt, creationCode);

        salt = keccak256(abi.encodePacked("MockUSDC", nonce));
        creationCode = abi.encodePacked(type(MockUSDC).creationCode, abi.encode("Mock USDC", "USDC", 18, faucetAddr));
        address mockUSDCAddr = IOutrunDeployer(outrunDeployer).deploy(salt, creationCode);

        salt = keccak256(abi.encodePacked("MockAUSDC", nonce));
        creationCode = abi.encodePacked(
            type(MockAUSDC).creationCode, abi.encode("Mock aUSDC", "aUSDC", 18, mockUSDCAddr, faucetAddr)
        );
        address mockAUSDCAddr = IOutrunDeployer(outrunDeployer).deploy(salt, creationCode);

        salt = keccak256(abi.encodePacked("MockSUSDS", nonce));
        creationCode = abi.encodePacked(
            type(MockSUSDS).creationCode, abi.encode("Mock sUSDS", "sUSDS", 18, mockUSDCAddr, faucetAddr)
        );
        address mockSUSDSAddr = IOutrunDeployer(outrunDeployer).deploy(salt, creationCode);

        IFaucet(faucetAddr).addToken(mockUSDCAddr, 1000000 * 1e18);
        IFaucet(faucetAddr).addToken(mockAUSDCAddr, 1000000 * 1e18);
        IFaucet(faucetAddr).addToken(mockSUSDSAddr, 1000000 * 1e18);

        console.log("Faucet deployed on %s", faucetAddr);
        console.log("MockUSDC deployed on %s", mockUSDCAddr);
        console.log("MockAUSDC deployed on %s", mockAUSDCAddr);
        console.log("MockSUSDS deployed on %s", mockSUSDSAddr);
    }

    function _deployMockOracle(uint256 nonce) internal {
        bytes32 salt = keccak256(abi.encodePacked("MockAUSDCOracle", nonce));
        bytes memory creationCode = abi.encodePacked(type(MockAUSDCOracle).creationCode, abi.encode(owner));
        address mockAUSDCOracle = IOutrunDeployer(outrunDeployer).deploy(salt, creationCode);

        salt = keccak256(abi.encodePacked("MockSUSDSOracle", nonce));
        creationCode = abi.encodePacked(type(MockSUSDSOracle).creationCode, abi.encode(owner));
        address mockSUSDSOracle = IOutrunDeployer(outrunDeployer).deploy(salt, creationCode);

        console.log("MockAUSDCOracle deployed on %s", mockAUSDCOracle);
        console.log("MockSUSDSOracle deployed on %s", mockSUSDSOracle);
    }

    function _deployMockERC20SY(uint256 nonce) internal {
        bytes32 salt = keccak256(abi.encodePacked("MockOutrunAUSDCSY", nonce));
        bytes memory creationCode = abi.encodePacked(
            type(MockOutrunAUSDCSY).creationCode,
            abi.encode(
                owner, vm.envAddress("MOCK_USDC"), vm.envAddress("MOCK_AUSDC"), vm.envAddress("MOCK_AUSDC_ORACLE")
            )
        );
        address aUSDCSYAddress = IOutrunDeployer(outrunDeployer).deploy(salt, creationCode);
        console.log("SY_AUSDC deployed on %s", aUSDCSYAddress);

        salt = keccak256(abi.encodePacked("MockOutrunSUSDSSY", nonce));
        creationCode = abi.encodePacked(
            type(MockOutrunSUSDSSY).creationCode,
            abi.encode(
                owner, vm.envAddress("MOCK_USDC"), vm.envAddress("MOCK_SUSDS"), vm.envAddress("MOCK_SUSDS_ORACLE")
            )
        );
        address sUSDSSYAddress = IOutrunDeployer(outrunDeployer).deploy(salt, creationCode);
        console.log("SY_SUSDS deployed on %s", sUSDSSYAddress);
    }

    // Mock aUSDC
    function _supportMockAUSDC(uint256 nonce) internal {
        address aUSDCSYAddress = vm.envAddress("MOCK_AUSDC_SY");
        _validateMockSupportConfig(aUSDCSYAddress);
        bytes32 salt = keccak256(abi.encodePacked("Mock SP aUSDC", nonce));
        bytes memory creationCode = abi.encodePacked(
            type(OutrunStakingPosition).creationCode, abi.encode(owner, 0, revenuePool, aUSDCSYAddress, uusd)
        );
        address aUSDCSPAddress = IOutrunDeployer(outrunDeployer).deploy(salt, creationCode);

        IOutrunStakeManager(aUSDCSPAddress).setKeeper(keeper);
        IUniversalAssets(uusd).setMintingCap(aUSDCSPAddress, 1000000000 ether);

        console.log("SP_AUSDC deployed on %s", aUSDCSPAddress);
    }

    // Mock sUSDS
    function _supportMockSUSDS(uint256 nonce) internal {
        address sUSDSSYAddress = vm.envAddress("MOCK_SUSDS_SY");
        _validateMockSupportConfig(sUSDSSYAddress);
        bytes32 salt = keccak256(abi.encodePacked("Mock SP sUSDS", nonce));
        bytes memory creationCode = abi.encodePacked(
            type(OutrunStakingPosition).creationCode, abi.encode(owner, 0, revenuePool, sUSDSSYAddress, uusd)
        );
        address sUSDSSPAddress = IOutrunDeployer(outrunDeployer).deploy(salt, creationCode);

        IOutrunStakeManager(sUSDSSPAddress).setKeeper(keeper);
        IUniversalAssets(uusd).setMintingCap(sUSDSSPAddress, 1000000000 ether);

        console.log("SP_SUSDS deployed on %s", sUSDSSPAddress);
    }

    function _validateMockSupportConfig(address sy) internal view {
        if (owner != deployer) revert InvalidOwner();
        if (keeper == address(0)) revert InvalidKeeper();
        if (outrunDeployer == address(0) || revenuePool == address(0) || sy == address(0) || uusd == address(0)) {
            revert InvalidAddress();
        }
        if (outrunDeployer.code.length == 0 || sy.code.length == 0 || uusd.code.length == 0) {
            revert InvalidAddress();
        }

        try IOwnable(uusd).owner() returns (address uusdOwner) {
            if (uusdOwner != owner) revert InvalidOwner();
        } catch {
            revert InvalidOwner();
        }

        try IStandardizedYield(sy).exchangeRate() returns (uint256 exchangeRate) {
            if (exchangeRate == 0) revert InvalidAddress();
        } catch {
            revert InvalidAddress();
        }
    }

    function _deployOutrunRouter(uint256 nonce) internal {
        bytes32 salt = keccak256(abi.encodePacked("OutrunRouter", nonce));
        bytes memory creationCode =
            abi.encodePacked(type(OutrunRouter).creationCode, abi.encode(owner, memeverseLauncher));
        address outrunRouterAddr = IOutrunDeployer(outrunDeployer).deploy(salt, creationCode);

        console.log("OutrunRouter deployed on %s", outrunRouterAddr);
    }

    function _crossChainOFT() internal {
        bytes memory receiveOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(85000, 0);
        SendParam memory sendUAssetParam = SendParam({
            dstEid: vm.envUint("SCROLL_SEPOLIA_EID").toUint32(),
            to: bytes32(uint256(uint160(owner))),
            amountLD: 500000 * 1e18,
            minAmountLD: 0,
            extraOptions: receiveOptions,
            composeMsg: abi.encode(),
            oftCmd: abi.encode()
        });
        MessagingFee memory messagingFee = IOFT(uusd).quoteSend(sendUAssetParam, false);
        IOFT(uusd).send{value: messagingFee.nativeFee}(sendUAssetParam, messagingFee, msg.sender);
    }

    function _updateRouterLauncher() internal {
        IOutrunRouter(outrunRouter).setMemeverseLauncher(memeverseLauncher);
    }
}
