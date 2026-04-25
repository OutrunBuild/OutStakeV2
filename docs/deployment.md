# 部署文档

## 文档目的

本文仅基于当前仓库的本地实现，整理 `script/deploy/**`、`script/lib/BaseScript.s.sol`、`foundry.toml`、`README.md` 以及这些脚本直接引用的生产合约所暴露出的部署表面。本文只描述当前代码已经实现的部署入口、依赖关系、配置项和注意事项，不讨论路线图或未来方案。

## 当前部署表面

当前仓库是 `Foundry-only workspace`。`README.md` 明确把部署相关目录限定在 `script/{deploy,lib,ops,process}`，`foundry.toml` 则提供了 Foundry profile、RPC alias 与 explorer 配置。

当前部署源码表面由以下文件组成：

- `script/lib/BaseScript.s.sol`
- `script/deploy/OutstakeScript.s.sol`
- `script/deploy/YieldDeployScript.s.sol`
- `script/deploy/deployment/OutrunDeployer.sol`
- `script/deploy/deployment/interfaces/IOutrunDeployer.sol`

其中，`BaseScript` 负责统一广播上下文：

- `setUp()` 从环境变量读取 `PRIVATE_KEY`
- 通过 `vm.rememberKey(privateKey)` 推导广播地址 `deployer`
- `broadcaster` modifier 在 `run()` 外层执行 `vm.startBroadcast(deployer)` / `vm.stopBroadcast()`

按当前 `run()` 实现，默认实际执行的部署面是：

- `OutstakeScript.run()`：读取环境变量，执行 `_chainsInit()`，然后执行 `_deployOutrunRouter(7)`
- `YieldDeployScript.run()`：读取环境变量，然后执行 `_supportAUSDC()`

同一批脚本里还存在若干辅助部署函数，但它们在当前 `run()` 中都被注释掉，没有自动执行：

- `OutstakeScript` 内的 `_deployOutrunDeployer`、`_deployUETH`、`_deployUUSD`、`_deployUBNB`、`_crossChainOFT`、`_updateRouterLauncher`
- `OutstakeScript` 内的 mock / faucet / mock oracle / mock SY / mock staking position 部署辅助函数
- `YieldDeployScript` 内的 `_supportWstETHOnSepolia()`、`_supportSUSDeOnSepolia()`

## `OutrunDeployer`

`OutrunDeployer` 是部署脚本使用的确定性部署工厂，构造函数只接收一个 `_owner`，并把所有权交给该地址。

当前实现有两个关键点：

- `deploy(bytes32 salt, bytes calldata creationCode)` 带 `onlyOwner`
- 真正传给 `CREATE3.deploy` 的 salt 不是原始入参，而是 `keccak256(abi.encodePacked(msg.sender, salt))`

这意味着：

- 只有 `owner` 能通过 `OutrunDeployer` 发起部署
- 同一个原始 salt，在不同 `msg.sender` 下会落到不同 namespace
- `getDeployed(deployer, salt)` 也使用同样的 `keccak256(deployer, salt)` 规则推导地址

`OutstakeScript` 里还有一个单独的 `_deployOutrunDeployer(uint256 nonce)` 辅助函数。它不是通过 `OutrunDeployer` 自部署，而是直接调用 OpenZeppelin `Create2.deploy` 部署 `OutrunDeployer` 本身，salt 为：

`keccak256(abi.encodePacked(owner, "OutrunDeployer", nonce))`

因此当前部署层次是两段式：

1. 先用 `CREATE2` 部署 `OutrunDeployer`
2. 再通过 `OutrunDeployer.deploy(...)` 用 `CREATE3` 部署 Router、uAsset、mock surface 或其他合约

## `OutstakeScript.s.sol`

`OutstakeScript` 同时承载了生产部署辅助函数与测试辅助部署函数，但当前 `run()` 实际只做两件事：

1. `_chainsInit()`
2. `_deployOutrunRouter(7)`

### 当前 `run()` 默认执行路径会读取的环境变量

- `UETH`
- `UUSD`
- `UBNB`
- `OWNER`
- `KEEPER`
- `REVENUE_POOL`
- `OUTRUN_DEPLOYER`
- `OUTRUN_ROUTER`
- `MEMEVERSE_LAUNCHER`
- `_chainsInit()` 还会额外读取各链的 endpoint / eid 环境变量；下文会单独展开

### `_chainsInit()`

`_chainsInit()` 会把 LayerZero endpoint 地址和 endpoint id 写入两个 mapping：

- `endpoints[chainId]`
- `endpointIds[chainId]`

当前覆盖的链有：

- `97` `BSC Testnet`
- `84532` `Base Sepolia`
- `421614` `Arbitrum Sepolia`
- `43113` `Avalanche Fuji`
- `80002` `Polygon Amoy`
- `57054` `Sonic Testnet`
- `11155420` `Optimistic Sepolia`
- `300` `ZKsync Sepolia`
- `59141` `Linea Sepolia`
- `168587773` `Blast Sepolia`
- `534351` `Scroll Sepolia`
- `10143` `Monad Testnet`
- `80069` `Bera Sepolia`
- `11155111` `Ethereum Sepolia`

### `_deployOutrunRouter(7)`

当前默认启用的部署动作是部署 `OutrunRouter`：

- 原始 salt：`keccak256(abi.encodePacked("OutrunRouter", 7))`
- 部署入口：`IOutrunDeployer(outrunDeployer).deploy(salt, creationCode)`
- 构造参数：`abi.encode(owner, memeverseLauncher)`

被部署的 `OutrunRouter` 构造函数非常简单，只做两件事：

- `Ownable(_owner)`
- 记录 `memeverseLauncher`

Router 本身不在部署时绑定任何 `SY`、`OutrunStakingPosition` 或 `uAsset`，它只是保留一个 launcher 地址，并在运行期通过接口与 `IStandardizedYield`、`IOutrunStakeManager` 交互。

### 当前脚本内存在但未默认执行的生产辅助能力

`OutstakeScript` 还实现了以下辅助函数：

- `_deployUETH(uint256 nonce)`
- `_deployUUSD(uint256 nonce)`
- `_deployUBNB(uint256 nonce)`
- `_updateRouterLauncher()`
- `_crossChainOFT()`

其中：

- `_deployUETH/_deployUUSD/_deployUBNB` 会部署 `OutrunUniversalAssets`
- `OutrunUniversalAssets` 当前构造参数固定为 `name`、`symbol`、`18`、当前链 endpoint、`owner`
- 脚本随后会对远端 `endpointId` 调用 `IOAppCore(...).setPeer(endpointId, peer)`
- `peer` 取值是当前刚部署出的本链地址转成 `bytes32`

从脚本实现看，这套写法假定跨链 peer 地址使用同一地址编码；脚本本身没有额外校验远端地址是否已经与本链部署结果一致。

`_crossChainOFT()` 也是现成辅助函数，但当前未在 `run()` 里启用。它会：

- 以 `uusd` 作为发送资产
- 把目标 `dstEid` 固定为 `SCROLL_SEPOLIA_EID`
- 发送 `500000 * 1e18`
- 使用 `OptionsBuilder` 构造 `lzReceive` gas 选项 `85000`

### 当前脚本内存在但未默认执行的测试辅助能力

`OutstakeScript` 还混入了测试支撑部署能力：

- `Faucet`
- `MockUSDC`
- `MockAUSDC`
- `MockSUSDS`
- `MockAUSDCOracle`
- `MockSUSDSOracle`
- `MockOutrunAUSDCSY`
- `MockOutrunSUSDSSY`
- 对应的 mock staking position 支持函数

这些函数通过同一个 `OutrunDeployer` 部署测试资产、测试 SY 和测试 position，但它们都不属于当前默认执行路径。

## `YieldDeployScript.s.sol`

`YieldDeployScript` 负责把某个收益适配器 `SY` 和对应的 `OutrunStakingPosition` 组合起来，并把 position 授权成目标 `uAsset` 的 minter。

### 当前 `run()` 读取的环境变量

- `UETH`
- `UUSD`
- `UBNB`
- `OWNER`
- `REVENUE_POOL`
- `KEEPER`

### 当前 `run()` 默认执行逻辑

当前默认启用的是：

- `_supportAUSDC()`

注释掉但已实现的辅助逻辑是：

- `_supportWstETHOnSepolia()`
- `_supportSUSDeOnSepolia()`

### `_supportAUSDC()`

`_supportAUSDC()` 只在以下两条链上生效，否则直接 `return`：

- `ARBITRUM_SEPOLIA_CHAINID`
- `BASE_SEPOLIA_CHAINID`

它的部署顺序是：

1. 读取对应链上的 `aUSDC` 和 `Aave Pool` 地址
2. 部署 `OutrunAaveV3SY("SY AaveE aUSDC", "SY aUSDC", aUSDC, aavePool, owner)`
3. 部署 `OutrunStakingPosition(owner, 0, revenuePool, aUSDCSYAddress, UUSD)`
4. 调用 `SP_aUSDC.setKeeper(keeper)`
5. 调用 `IUniversalAssets(UUSD).setMintingCap(aUSDCSPAddress, 1000000000 ether)`

这说明当前 aUSDC 支持面把：

- `OutrunAaveV3SY` 作为收益入口
- `OutrunStakingPosition` 作为 position / debt 记录层
- `UUSD` 作为铸造出来的 uAsset

串成了一条完整路径。

### 当前文件里已实现但未默认启用的两个 Sepolia 支持面

`_supportWstETHOnSepolia()` 只在 `ETHEREUM_SEPOLIA_CHAINID` 生效，部署：

- `OutrunWstETHSY(owner, stETH, wstETH)`
- `OutrunStakingPosition(owner, 0, revenuePool, wstETHSYAddress, UETH)`
- 然后给 position 设置 `keeper`
- 再给 `UETH` 设置 `mintingCap = 1000000000 ether`

`_supportSUSDeOnSepolia()` 也只在 `ETHEREUM_SEPOLIA_CHAINID` 生效，部署：

- `OutrunStakedUSDeSY(owner, USDe, sUSDe)`
- `OutrunStakingPosition(owner, 0, revenuePool, sUSDeSYAddress, UUSD)`
- 然后给 position 设置 `keeper`
- 再给 `UUSD` 设置 `mintingCap = 1000000000 ether`

## 主要 env / config 表面

### BaseScript 广播环境

- `PRIVATE_KEY`

这是所有脚本共享的最底层广播前提。

### Foundry 配置表面

`foundry.toml` 当前给出了以下部署相关配置：

- `solc = "0.8.30"`
- `evm_version = "prague"`
- `via_ir = true`
- `build_info = true`
- `extra_output = ["storageLayout"]`

同时还配置了 RPC alias：

- `bsc_testnet`
- `base_sepolia`
- `arbitrum_sepolia`
- `sepolia`
- `avalanche_fuji`
- `polygon_amoy`
- `sonic_testnet`
- `optimistic_sepolia`
- `zksync_sepolia`
- `linea_sepolia`
- `blast_sepolia`
- `scroll_sepolia`
- `monad_testnet`
- `bera_sepolia`
- `bsc_mainnet`

这些 alias 背后依赖的环境变量分别是 `*_RPC`。

Explorer 配置则依赖：

- `ETHEREUMSCAN_API_KEY`
- `ETHEREUMSCAN_API_URL`

并为多个测试网和 `bsc_mainnet` 提供了 `etherscan` profile。

### `OutstakeScript` 主要 env

共享角色与地址：

- `OWNER`
- `KEEPER`
- `REVENUE_POOL`
- `OUTRUN_DEPLOYER`
- `OUTRUN_ROUTER`
- `MEMEVERSE_LAUNCHER`
- `UETH`
- `UUSD`
- `UBNB`

LayerZero endpoint / eid：

- `BSC_TESTNET_ENDPOINT` / `BSC_TESTNET_EID`
- `BASE_SEPOLIA_ENDPOINT` / `BASE_SEPOLIA_EID`
- `ARBITRUM_SEPOLIA_ENDPOINT` / `ARBITRUM_SEPOLIA_EID`
- `AVALANCHE_FUJI_ENDPOINT` / `AVALANCHE_FUJI_EID`
- `POLYGON_AMOY_ENDPOINT` / `POLYGON_AMOY_EID`
- `SONIC_TESTNET_ENDPOINT` / `SONIC_TESTNET_EID`
- `OPTIMISTIC_SEPOLIA_ENDPOINT` / `OPTIMISTIC_SEPOLIA_EID`
- `ZKSYNC_SEPOLIA_ENDPOINT` / `ZKSYNC_SEPOLIA_EID`
- `LINEA_SEPOLIA_ENDPOINT` / `LINEA_SEPOLIA_EID`
- `BLAST_SEPOLIA_ENDPOINT` / `BLAST_SEPOLIA_EID`
- `SCROLL_SEPOLIA_ENDPOINT` / `SCROLL_SEPOLIA_EID`
- `MONAD_TESTNET_ENDPOINT` / `MONAD_TESTNET_EID`
- `BERA_SEPOLIA_ENDPOINT` / `BERA_SEPOLIA_EID`
- `ETHEREUM_SEPOLIA_ENDPOINT` / `ETHEREUM_SEPOLIA_EID`

mock 支持相关 env：

- `MOCK_USDC`
- `MOCK_AUSDC`
- `MOCK_SUSDS`
- `MOCK_AUSDC_ORACLE`
- `MOCK_SUSDS_ORACLE`
- `MOCK_AUSDC_SY`
- `MOCK_SUSDS_SY`

### `YieldDeployScript` 主要 env

链选择与协议地址：

- `ETHEREUM_SEPOLIA_CHAINID`
- `SEPOLIA_STETH`
- `SEPOLIA_WSTETH`
- `SEPOLIA_USDE`
- `SEPOLIA_SUSDE`
- `ARBITRUM_SEPOLIA_CHAINID`
- `ARBITRUM_SEPOLIA_AUSDC`
- `ARBITRUM_SEPOLIA_POOL`
- `BASE_SEPOLIA_CHAINID`
- `BASE_SEPOLIA_AUSDC`
- `BASE_SEPOLIA_POOL`

共享角色与地址：

- `OWNER`
- `KEEPER`
- `REVENUE_POOL`
- `UETH`
- `UUSD`
- `UBNB`

## 当前部署关系总结

按当前实现，部署关系可以概括为以下几层：

1. `BaseScript` 决定广播身份，所有部署动作都默认由 `PRIVATE_KEY` 对应地址发起。
2. `OutrunDeployer` 是确定性部署工厂，Factory 自己由 `_deployOutrunDeployer()` 用 `CREATE2` 部署，其余合约可由它再用 `CREATE3` 部署。
3. `OutrunUniversalAssets` 是 uAsset 层，position 本身不会在构造函数里自动获得铸造权限，必须由 owner 显式调用 `setMintingCap(position, cap)`。
4. `OutrunStakingPosition` 是 position / debt / keeper / revenuePool 逻辑层，当前脚本里所有 position 的 `minStake` 都被部署为 `0`。
5. `SY` 适配器是收益入口层。按 `YieldDeployScript.run()` 的当前默认行为，只启用 `OutrunAaveV3SY`（`_supportAUSDC()`）；`OutrunWstETHSY` 与 `OutrunStakedUSDeSY` 的支持路径也已写在脚本里，但当前仍处于注释掉、未默认启用的 helper 状态。
6. `OutrunRouter` 是独立的用户入口层，部署时只依赖 `owner` 与 `memeverseLauncher`，并不在脚本层直接绑定某个具体 `SY` 或 `position`。

按脚本里已经写好的组合关系，当前资产映射是：

- `wstETH SY -> OutrunStakingPosition -> UETH`
- `sUSDe SY -> OutrunStakingPosition -> UUSD`
- `aUSDC SY -> OutrunStakingPosition -> UUSD`

## 当前实现提醒

1. 当前 `OutstakeScript.run()` 并不会部署 `OutrunDeployer`、`UETH`、`UUSD`、`UBNB`，它默认假设 `OUTRUN_DEPLOYER` 已可用，并只执行 Router 部署。
2. 当前 `YieldDeployScript.run()` 也不会部署 `UETH`、`UUSD`、`UBNB`，而是默认这些地址已经存在，并且当前 `OWNER` 对这些 `uAsset` 仍然拥有 `setMintingCap` 权限。
3. `YieldDeployScript` 的多个支持函数在链不匹配时会直接 `return`，不会主动报错；因此脚本在错误网络上可能表现为“成功广播但没有部署任何目标合约”。
4. `OutrunDeployer.deploy()` 的地址命名空间绑定 `msg.sender`，所以即使原始 salt 不变，只要广播地址变了，预测地址和实际地址也会变化。
5. `_deployUETH/_deployUUSD/_deployUBNB` 虽然在 `_chainsInit()` 中初始化了 14 条链的 endpoint / eid，但实际写死在 `omnichainIds` 里的 peer 配置目前只覆盖 9 条链，其余链位仍保留为注释状态。
6. `_deployUETH/_deployUUSD/_deployUBNB` 当前只按最新构造参数部署 `OutrunUniversalAssets`。
7. `OutstakeScript` 把生产部署辅助和测试辅助部署放在同一个文件中；阅读或执行时需要区分哪些函数只是测试支撑，哪些函数才是生产表面。
