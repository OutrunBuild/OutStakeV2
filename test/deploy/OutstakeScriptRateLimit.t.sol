// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test, Vm} from "forge-std/Test.sol";
import {IOAppCore} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppCore.sol";
import {OutrunOFT} from "../../src/assets/omnichain/OutrunOFT.sol";
import {OutrunUniversalAssets} from "../../src/assets/base/OutrunUniversalAssets.sol";
import {IUniversalAssets} from "../../src/assets/interfaces/IUniversalAssets.sol";
import {IOutrunStakeManager} from "../../src/position/interfaces/IOutrunStakeManager.sol";
import {OutstakeScript} from "../../script/deploy/OutstakeScript.s.sol";
import {OutrunDeployer} from "../../script/deploy/deployment/OutrunDeployer.sol";
import {MockLzEndpoint} from "../assets/helpers/OFTTestHelper.sol";

interface IOutstakeScriptErrors {
    error InvalidEndpoint();
    error InvalidOwner();
    error InvalidOutboundRateLimit();
    error InvalidOutboundRateWindow();
    error InvalidKeeper();
    error InvalidAddress();
}

contract RevertingOutrunDeployer {
    error DeployWasCalled();

    function deploy(bytes32, bytes calldata) external pure returns (address) {
        revert DeployWasCalled();
    }
}

contract MockSY {
    function exchangeRate() external pure returns (uint256) {
        return 1e18;
    }
}

contract RevertingSY {
    error InvalidSY();

    function exchangeRate() external pure returns (uint256) {
        revert InvalidSY();
    }
}

contract ZeroRateSY {
    function exchangeRate() external pure returns (uint256) {
        return 0;
    }
}

contract OutstakeScriptHarness is OutstakeScript {
    uint256 internal rawRateLimit;
    uint256 internal rawRateWindow;
    uint256 internal uusdRateLimit;
    uint256 internal uusdRateWindow;
    uint256 internal ubnbRateLimit;
    uint256 internal ubnbRateWindow;

    function configure(address owner_, address outrunDeployer_, address deployer_) external {
        owner = owner_;
        outrunDeployer = outrunDeployer_;
        deployer = deployer_;
    }

    function configureSupport(
        address owner_,
        address outrunDeployer_,
        address deployer_,
        address revenuePool_,
        address keeper_,
        address uusd_
    ) external {
        owner = owner_;
        outrunDeployer = outrunDeployer_;
        deployer = deployer_;
        revenuePool = revenuePool_;
        keeper = keeper_;
        uusd = uusd_;
    }

    function setChainConfig(uint32 chainId, address endpoint, uint32 endpointId) external {
        endpoints[chainId] = endpoint;
        endpointIds[chainId] = endpointId;
    }

    function setRateLimitConfig(uint256 limit, uint256 window) external {
        rawRateLimit = limit;
        rawRateWindow = window;
    }

    function setUUSDRateLimitConfig(uint256 limit, uint256 window) external {
        uusdRateLimit = limit;
        uusdRateWindow = window;
    }

    function setUBNBRateLimitConfig(uint256 limit, uint256 window) external {
        ubnbRateLimit = limit;
        ubnbRateWindow = window;
    }

    function deployUETH(uint256 nonce) external {
        _deployUETH(nonce);
    }

    function deployUUSD(uint256 nonce) external {
        _deployUUSD(nonce);
    }

    function deployUBNB(uint256 nonce) external {
        _deployUBNB(nonce);
    }

    function chainsInit() external {
        _chainsInit();
    }

    function supportMockAUSDC(uint256 nonce) external {
        _supportMockAUSDC(nonce);
    }

    function deployMockERC20(uint256 nonce) external {
        _deployMockERC20(nonce);
    }

    function _rawOutboundRateLimitConfig(string memory limitEnv, string memory)
        internal
        view
        override
        returns (uint256 limit, uint256 window)
    {
        if (keccak256(bytes(limitEnv)) == keccak256("UUSD_OUTBOUND_RATE_LIMIT")) {
            return (uusdRateLimit, uusdRateWindow);
        }

        if (keccak256(bytes(limitEnv)) == keccak256("UBNB_OUTBOUND_RATE_LIMIT")) {
            return (ubnbRateLimit, ubnbRateWindow);
        }

        limit = rawRateLimit;
        window = rawRateWindow;
    }
}

contract OutstakeScriptRateLimitTest is Test {
    bytes32 internal constant RATE_LIMIT_SET_TOPIC = keccak256("OutboundRateLimitSet(uint32,uint192,uint64)");
    bytes32 internal constant PEER_SET_TOPIC = keccak256("PeerSet(uint32,bytes32)");
    bytes32 internal constant SET_KEEPER_TOPIC = keccak256("SetKeeper(address)");
    bytes32 internal constant SET_MINTING_CAP_TOPIC = keccak256("SetMintingCap(address,uint256,uint256)");

    uint32 internal constant LOCAL_CHAIN_ID = 97;
    uint256 internal constant UETH_LIMIT = 1_000_000;
    uint256 internal constant UETH_WINDOW = 1 hours;
    uint256 internal constant UUSD_LIMIT = 2_000_000;
    uint256 internal constant UUSD_WINDOW = 2 hours;
    uint256 internal constant UBNB_LIMIT = 3_000_000;
    uint256 internal constant UBNB_WINDOW = 3 hours;
    uint256 internal constant SUPPORT_MINT_CAP = 1000000000 ether;

    OutstakeScriptHarness internal script;
    MockLzEndpoint internal endpoint;

    function setUp() external {
        vm.chainId(LOCAL_CHAIN_ID);
        script = new OutstakeScriptHarness();
        endpoint = new MockLzEndpoint();
        _resetConfig();
        _setEnv("MOCK_AUSDC_SY", vm.toString(address(0xA11CE)));
    }

    function testDeployUETHSetsPeersAndOutboundRateLimitsForAllNonSelfPeers() external {
        _resetConfig();
        OutrunDeployer deployer = new OutrunDeployer(address(script));
        script.configure(address(script), address(deployer), address(script));

        script.deployUETH(1);

        address ueth = _deployedUETH(address(deployer), address(script), 1);
        bytes32 peer = bytes32(uint256(uint160(ueth)));
        uint32[] memory omnichainIds = _uethOmnichainIds();

        for (uint256 i; i < omnichainIds.length; ++i) {
            uint32 omnichainId = omnichainIds[i];
            if (omnichainId == block.chainid) continue;

            uint32 endpointId = script.endpointIds(omnichainId);
            assertEq(IOAppCore(ueth).peers(endpointId), peer);

            (uint256 amountInFlight,, uint256 limit, uint256 window) = OutrunOFT(ueth).rateLimits(endpointId);
            assertEq(amountInFlight, 0);
            assertEq(limit, UETH_LIMIT);
            assertEq(window, UETH_WINDOW);
        }
    }

    function testDeployUETHEmitsOutboundRateLimitBeforePeerSet() external {
        _resetConfig();
        OutrunDeployer deployer = new OutrunDeployer(address(script));
        script.configure(address(script), address(deployer), address(script));

        vm.recordLogs();
        script.deployUETH(1);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256 firstRateLimit = type(uint256).max;
        uint256 firstPeerSet = type(uint256).max;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == RATE_LIMIT_SET_TOPIC && firstRateLimit == type(uint256).max) {
                firstRateLimit = i;
            }
            if (logs[i].topics[0] == PEER_SET_TOPIC && firstPeerSet == type(uint256).max) {
                firstPeerSet = i;
            }
        }

        assertLt(firstRateLimit, firstPeerSet);
    }

    function testDeployUETHEmitsOutboundRateLimitBeforePeerSetForEachEndpoint() external {
        _resetConfig();
        OutrunDeployer deployer = new OutrunDeployer(address(script));
        script.configure(address(script), address(deployer), address(script));

        vm.recordLogs();
        script.deployUETH(1);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint32[] memory omnichainIds = _uethOmnichainIds();
        for (uint256 i; i < omnichainIds.length; ++i) {
            uint32 omnichainId = omnichainIds[i];
            if (omnichainId == block.chainid) continue;

            uint32 endpointId = script.endpointIds(omnichainId);
            uint256 rateLimitLog = type(uint256).max;
            uint256 peerSetLog = type(uint256).max;

            for (uint256 j; j < logs.length; ++j) {
                if (logs[j].topics.length == 0) continue;
                if (logs[j].topics[0] != RATE_LIMIT_SET_TOPIC && logs[j].topics[0] != PEER_SET_TOPIC) continue;
                if (_logEndpointId(logs[j]) != endpointId) continue;

                if (logs[j].topics[0] == RATE_LIMIT_SET_TOPIC && rateLimitLog == type(uint256).max) {
                    rateLimitLog = j;
                }
                if (logs[j].topics[0] == PEER_SET_TOPIC && peerSetLog == type(uint256).max) {
                    peerSetLog = j;
                }
            }

            assertLt(rateLimitLog, peerSetLog);
        }
    }

    function testZeroOutboundRateLimitRevertsBeforeDeploy() external {
        _resetConfig();
        script.setRateLimitConfig(0, UETH_WINDOW);
        RevertingOutrunDeployer deployer = new RevertingOutrunDeployer();
        script.configure(address(script), address(deployer), address(script));

        vm.expectRevert(IOutstakeScriptErrors.InvalidOutboundRateLimit.selector);
        script.deployUETH(1);
    }

    function testZeroOutboundRateWindowRevertsBeforeDeploy() external {
        _resetConfig();
        script.setRateLimitConfig(UETH_LIMIT, 0);
        RevertingOutrunDeployer deployer = new RevertingOutrunDeployer();
        script.configure(address(script), address(deployer), address(script));

        vm.expectRevert(IOutstakeScriptErrors.InvalidOutboundRateWindow.selector);
        script.deployUETH(1);
    }

    function testOwnerMismatchRevertsBeforeDeploy() external {
        _resetConfig();
        RevertingOutrunDeployer deployer = new RevertingOutrunDeployer();
        script.configure(address(0xBEEF), address(deployer), address(script));

        vm.expectRevert(IOutstakeScriptErrors.InvalidOwner.selector);
        script.deployUETH(1);
    }

    function testZeroLocalEndpointRevertsBeforeDeploy() external {
        _resetConfig();
        script.setChainConfig(LOCAL_CHAIN_ID, address(0), 1001);
        RevertingOutrunDeployer deployer = new RevertingOutrunDeployer();
        script.configure(address(script), address(deployer), address(script));

        vm.expectRevert(IOutstakeScriptErrors.InvalidEndpoint.selector);
        script.deployUETH(1);
    }

    function testLocalEndpointWithoutCodeRevertsBeforeDeploy() external {
        _resetConfig();
        script.setChainConfig(LOCAL_CHAIN_ID, address(0xCAFE), 1001);
        RevertingOutrunDeployer deployer = new RevertingOutrunDeployer();
        script.configure(address(script), address(deployer), address(script));

        vm.expectRevert(IOutstakeScriptErrors.InvalidEndpoint.selector);
        script.deployUETH(1);
    }

    function testLocalEndpointIdMismatchRevertsBeforeDeploy() external {
        _resetConfig();
        endpoint.setEid(9999);
        RevertingOutrunDeployer deployer = new RevertingOutrunDeployer();
        script.configure(address(script), address(deployer), address(script));

        vm.expectRevert(IOutstakeScriptErrors.InvalidEndpoint.selector);
        script.deployUETH(1);
    }

    function testMissingRemoteEndpointIdRevertsBeforeDeploy() external {
        _resetConfig();
        script.setChainConfig(84532, address(endpoint), 0);
        RevertingOutrunDeployer deployer = new RevertingOutrunDeployer();
        script.configure(address(script), address(deployer), address(script));

        vm.expectRevert(OutstakeScript.InvalidOmnichainId.selector);
        script.deployUETH(1);
    }

    function testChainsInitRevertsWhenEndpointIdExceedsUint32() external {
        _setChainEnv();
        _setEnv("BSC_TESTNET_EID", vm.toString(uint256(type(uint32).max) + 1));

        vm.expectRevert();
        script.chainsInit();
    }

    function testDeployUUSDAndUBNBUseDistinctRateLimitConfigPaths() external {
        _resetConfig();
        script.setUUSDRateLimitConfig(UUSD_LIMIT, UUSD_WINDOW);
        script.setUBNBRateLimitConfig(UBNB_LIMIT, UBNB_WINDOW);
        OutrunDeployer deployer = new OutrunDeployer(address(script));
        script.configure(address(script), address(deployer), address(script));

        script.deployUUSD(1);
        script.deployUBNB(2);

        address uusd = _deployedUUSD(address(deployer), address(script), 1);
        address ubnb = _deployedUBNB(address(deployer), address(script), 2);
        uint32 endpointId = script.endpointIds(84532);
        (,, uint256 uusdLimit, uint256 uusdWindow) = OutrunOFT(uusd).rateLimits(endpointId);
        (,, uint256 ubnbLimit, uint256 ubnbWindow) = OutrunOFT(ubnb).rateLimits(endpointId);

        assertEq(uusdLimit, UUSD_LIMIT);
        assertEq(uusdWindow, UUSD_WINDOW);
        assertEq(ubnbLimit, UBNB_LIMIT);
        assertEq(ubnbWindow, UBNB_WINDOW);
    }

    function testSupportMockAUSDCRevertsForZeroKeeperBeforeDeploy() external {
        OutrunUniversalAssets uAsset = _deployOwnedUAsset(address(script));
        RevertingOutrunDeployer deployer = new RevertingOutrunDeployer();
        script.configureSupport(
            address(script), address(deployer), address(script), address(0xB0B), address(0), address(uAsset)
        );

        vm.expectRevert(IOutstakeScriptErrors.InvalidKeeper.selector);
        script.supportMockAUSDC(1);
    }

    function testSupportMockAUSDCRevertsForOwnerMismatchBeforeDeploy() external {
        OutrunUniversalAssets uAsset = _deployOwnedUAsset(address(script));
        RevertingOutrunDeployer deployer = new RevertingOutrunDeployer();
        script.configureSupport(
            address(0xBEEF), address(deployer), address(script), address(0xB0B), address(0xCAFE), address(uAsset)
        );

        vm.expectRevert(IOutstakeScriptErrors.InvalidOwner.selector);
        script.supportMockAUSDC(1);
    }

    function testSupportMockAUSDCSetsKeeperBeforeMintCap() external {
        OutrunUniversalAssets uAsset = _deployOwnedUAsset(address(script));
        MockSY sy = new MockSY();
        OutrunDeployer deployer = new OutrunDeployer(address(script));
        script.configureSupport(
            address(script), address(deployer), address(script), address(0xB0B), address(0xCAFE), address(uAsset)
        );
        _setEnv("MOCK_AUSDC_SY", vm.toString(address(sy)));

        vm.recordLogs();
        script.supportMockAUSDC(1);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        address position = _deployedMockAUSDCSP(address(deployer), address(script), 1);
        uint256 keeperLog = type(uint256).max;
        uint256 mintCapLog = type(uint256).max;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == SET_KEEPER_TOPIC && logs[i].emitter == position) {
                keeperLog = i;
            }
            if (logs[i].topics[0] == SET_MINTING_CAP_TOPIC && logs[i].emitter == address(uAsset)) {
                mintCapLog = i;
            }
        }

        assertLt(keeperLog, mintCapLog);
        assertEq(IOutrunStakeManager(position).keeper(), address(0xCAFE));
        assertEq(IUniversalAssets(address(uAsset)).checkMintableAmount(position), SUPPORT_MINT_CAP);
    }

    function testSupportMockAUSDCRevertsForNonContractUUSDBeforeDeploy() external {
        MockSY sy = new MockSY();
        RevertingOutrunDeployer deployer = new RevertingOutrunDeployer();
        script.configureSupport(
            address(script), address(deployer), address(script), address(0xB0B), address(0xCAFE), address(0xA11CE)
        );
        _setEnv("MOCK_AUSDC_SY", vm.toString(address(sy)));

        vm.expectRevert(IOutstakeScriptErrors.InvalidAddress.selector);
        script.supportMockAUSDC(1);
    }

    function testSupportMockAUSDCRevertsForWrongUUSDOwnerBeforeDeploy() external {
        OutrunUniversalAssets uAsset = _deployOwnedUAsset(address(0xBEEF));
        MockSY sy = new MockSY();
        RevertingOutrunDeployer deployer = new RevertingOutrunDeployer();
        script.configureSupport(
            address(script), address(deployer), address(script), address(0xB0B), address(0xCAFE), address(uAsset)
        );
        _setEnv("MOCK_AUSDC_SY", vm.toString(address(sy)));

        vm.expectRevert(IOutstakeScriptErrors.InvalidOwner.selector);
        script.supportMockAUSDC(1);
    }

    function testSupportMockAUSDCRevertsForNonContractSYBeforeDeploy() external {
        OutrunUniversalAssets uAsset = _deployOwnedUAsset(address(script));
        RevertingOutrunDeployer deployer = new RevertingOutrunDeployer();
        script.configureSupport(
            address(script), address(deployer), address(script), address(0xB0B), address(0xCAFE), address(uAsset)
        );
        _setEnv("MOCK_AUSDC_SY", vm.toString(address(0xA11CE)));

        vm.expectRevert(IOutstakeScriptErrors.InvalidAddress.selector);
        script.supportMockAUSDC(1);
    }

    function testSupportMockAUSDCRevertsForSYReadFailureBeforeDeploy() external {
        OutrunUniversalAssets uAsset = _deployOwnedUAsset(address(script));
        RevertingSY sy = new RevertingSY();
        RevertingOutrunDeployer deployer = new RevertingOutrunDeployer();
        script.configureSupport(
            address(script), address(deployer), address(script), address(0xB0B), address(0xCAFE), address(uAsset)
        );
        _setEnv("MOCK_AUSDC_SY", vm.toString(address(sy)));

        vm.expectRevert(IOutstakeScriptErrors.InvalidAddress.selector);
        script.supportMockAUSDC(1);
    }

    function testSupportMockAUSDCRevertsForZeroSYExchangeRateBeforeDeploy() external {
        OutrunUniversalAssets uAsset = _deployOwnedUAsset(address(script));
        ZeroRateSY sy = new ZeroRateSY();
        RevertingOutrunDeployer deployer = new RevertingOutrunDeployer();
        script.configureSupport(
            address(script), address(deployer), address(script), address(0xB0B), address(0xCAFE), address(uAsset)
        );
        _setEnv("MOCK_AUSDC_SY", vm.toString(address(sy)));

        vm.expectRevert(IOutstakeScriptErrors.InvalidAddress.selector);
        script.supportMockAUSDC(1);
    }

    function testDeployMockERC20RevertsForOwnerMismatchBeforeDeploy() external {
        RevertingOutrunDeployer deployer = new RevertingOutrunDeployer();
        script.configure(address(0xBEEF), address(deployer), address(script));

        vm.expectRevert(IOutstakeScriptErrors.InvalidOwner.selector);
        script.deployMockERC20(1);
    }

    function _resetConfig() internal {
        script.setRateLimitConfig(UETH_LIMIT, UETH_WINDOW);
        script.setUUSDRateLimitConfig(UETH_LIMIT, UETH_WINDOW);
        script.setUBNBRateLimitConfig(UETH_LIMIT, UETH_WINDOW);
        script.setChainConfig(97, address(endpoint), 1001);
        script.setChainConfig(84532, address(endpoint), 1002);
        script.setChainConfig(421614, address(endpoint), 1003);
        script.setChainConfig(43113, address(endpoint), 1004);
        script.setChainConfig(80002, address(endpoint), 1005);
        script.setChainConfig(57054, address(endpoint), 1006);
        script.setChainConfig(11155420, address(endpoint), 1007);
        script.setChainConfig(300, address(endpoint), 1008);
        script.setChainConfig(59141, address(endpoint), 1009);
        script.setChainConfig(168587773, address(endpoint), 1010);
        script.setChainConfig(534351, address(endpoint), 1011);
        script.setChainConfig(10143, address(endpoint), 1012);
        script.setChainConfig(80069, address(endpoint), 1013);
        script.setChainConfig(11155111, address(endpoint), 1014);
    }

    function _uethOmnichainIds() internal pure returns (uint32[] memory omnichainIds) {
        omnichainIds = new uint32[](9);
        omnichainIds[0] = 97;
        omnichainIds[1] = 84532;
        omnichainIds[2] = 421614;
        omnichainIds[3] = 43113;
        omnichainIds[4] = 80002;
        omnichainIds[5] = 57054;
        omnichainIds[6] = 168587773;
        omnichainIds[7] = 534351;
        omnichainIds[8] = 11155111;
    }

    function _deployedUETH(address deployer, address caller, uint256 nonce) internal view returns (address) {
        bytes32 salt = keccak256(abi.encodePacked("OmnichainUniversalAssetsETH", nonce));
        return OutrunDeployer(deployer).getDeployed(caller, salt);
    }

    function _logEndpointId(Vm.Log memory log) internal pure returns (uint32) {
        if (log.topics[0] == RATE_LIMIT_SET_TOPIC) return uint32(uint256(log.topics[1]));
        (uint32 endpointId,) = abi.decode(log.data, (uint32, bytes32));
        return endpointId;
    }

    function _deployedUUSD(address deployer, address caller, uint256 nonce) internal view returns (address) {
        bytes32 salt = keccak256(abi.encodePacked("OmnichainUniversalAssetsUSD", nonce));
        return OutrunDeployer(deployer).getDeployed(caller, salt);
    }

    function _deployedUBNB(address deployer, address caller, uint256 nonce) internal view returns (address) {
        bytes32 salt = keccak256(abi.encodePacked("OmnichainUniversalAssetsBNB", nonce));
        return OutrunDeployer(deployer).getDeployed(caller, salt);
    }

    function _deployedMockAUSDCSP(address deployer, address caller, uint256 nonce) internal view returns (address) {
        bytes32 salt = keccak256(abi.encodePacked("Mock SP aUSDC", nonce));
        return OutrunDeployer(deployer).getDeployed(caller, salt);
    }

    function _deployOwnedUAsset(address owner_) internal returns (OutrunUniversalAssets) {
        return new OutrunUniversalAssets("Test UUSD", "UUSD", 18, address(endpoint), owner_);
    }

    function _setChainEnv() internal {
        _setEnv("BSC_TESTNET_ENDPOINT", vm.toString(address(endpoint)));
        _setEnv("BASE_SEPOLIA_ENDPOINT", vm.toString(address(endpoint)));
        _setEnv("ARBITRUM_SEPOLIA_ENDPOINT", vm.toString(address(endpoint)));
        _setEnv("AVALANCHE_FUJI_ENDPOINT", vm.toString(address(endpoint)));
        _setEnv("POLYGON_AMOY_ENDPOINT", vm.toString(address(endpoint)));
        _setEnv("SONIC_TESTNET_ENDPOINT", vm.toString(address(endpoint)));
        _setEnv("OPTIMISTIC_SEPOLIA_ENDPOINT", vm.toString(address(endpoint)));
        _setEnv("ZKSYNC_SEPOLIA_ENDPOINT", vm.toString(address(endpoint)));
        _setEnv("LINEA_SEPOLIA_ENDPOINT", vm.toString(address(endpoint)));
        _setEnv("BLAST_SEPOLIA_ENDPOINT", vm.toString(address(endpoint)));
        _setEnv("SCROLL_SEPOLIA_ENDPOINT", vm.toString(address(endpoint)));
        _setEnv("MONAD_TESTNET_ENDPOINT", vm.toString(address(endpoint)));
        _setEnv("BERA_SEPOLIA_ENDPOINT", vm.toString(address(endpoint)));
        _setEnv("ETHEREUM_SEPOLIA_ENDPOINT", vm.toString(address(endpoint)));

        _setEnv("BSC_TESTNET_EID", "1001");
        _setEnv("BASE_SEPOLIA_EID", "1002");
        _setEnv("ARBITRUM_SEPOLIA_EID", "1003");
        _setEnv("AVALANCHE_FUJI_EID", "1004");
        _setEnv("POLYGON_AMOY_EID", "1005");
        _setEnv("SONIC_TESTNET_EID", "1006");
        _setEnv("OPTIMISTIC_SEPOLIA_EID", "1007");
        _setEnv("ZKSYNC_SEPOLIA_EID", "1008");
        _setEnv("LINEA_SEPOLIA_EID", "1009");
        _setEnv("BLAST_SEPOLIA_EID", "1010");
        _setEnv("SCROLL_SEPOLIA_EID", "1011");
        _setEnv("MONAD_TESTNET_EID", "1012");
        _setEnv("BERA_SEPOLIA_EID", "1013");
        _setEnv("ETHEREUM_SEPOLIA_EID", "1014");
    }

    function _setEnv(string memory key, string memory value) internal {
        // forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv(key, value);
    }
}
