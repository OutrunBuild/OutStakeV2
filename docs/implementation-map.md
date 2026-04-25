# OutStakeV2 Implementation Map

## 文档目的

本文档用于给出 `OutStakeV2` 当前实现面的结构化映射，说明各 surface 的职责、权限边界、本地依赖、证据来源与当前状态。

本文档只描述本仓库当前源码、测试与部署入口能够直接证明的实现事实。凡涉及外部协议、oracle、跨链消息、launcher 或 vault 行为，而本仓库无法单独证明其真实线上表现者，均作为本地依赖边界陈述，不升级为既成事实。

## Surface Map

| surface | core responsibility | authority/roles | key local dependencies | evidence source | current state |
| --- | --- | --- | --- | --- | --- |
| `OutrunUniversalAssets` | 作为统一 `uAsset` 资产层，维护按 minter 维度的 mint cap、已铸造债务、`mint` 与 `repay` 路径 | `owner` 可设置或撤销 minter cap；被授权 minter 可在额度内铸造并回收自身债务 | `IUniversalAssets`、`OutrunOFT`、`Ownable`、position/router 下游对 `mint/repay` 的调用 | `src/assets/base/OutrunUniversalAssets.sol`；`test/assets/OutrunUniversalAssets.t.sol` | 已实现且有直接测试，覆盖 mint cap、repay 与基础 OFT 安全边界 |
| `OutrunOFT` | 为 `uAsset` 提供 ERC20、pause 与 OFT 跨链铸烧表面 | OFT delegate/peer 配置由上层 owner 流程控制 | `OutrunERC20Pausable`、`OFTCore`、`RateLimiter` | `src/assets/omnichain/OutrunOFT.sol`；`test/assets/OutrunUniversalAssets.t.sol`；`test/assets/OutrunOFTRateLimit.t.sol` | 已实现；本地证明了 token、`_toSD`、rate-limit 行为，以及 `quoteOFT()` 对当前 outbound capacity 与 shared-decimal envelope 的约束 |
| `OutrunStakingPosition` | 管理锁仓仓位、可追加 `uAsset` 债务、到期赎回、keeper 代偿赎回、公共 wrap 池与 wrap 收益 harvest | `owner` 可 pause、配置 `minStake/uAsset/revenuePool/keeper`；`position owner` 管理自身仓位；`keeper` 仅能执行 `keepRedeem`；普通用户可进入 wrap 池 | `IStandardizedYield.exchangeRate/redeem/previewRedeem`、`IUniversalAssets.mint/repay`、`SYUtils`、`TokenHelper` | `src/position/OutrunStakingPosition.sol`；`test/position/OutrunStakingPosition.t.sol` | 已实现且核心路径有测试，覆盖 stake、draw、redeem、keepRedeem、wrapStake、wrapRedeem、harvestWrapYield |
| `OutrunRouter` | 把 `token <-> SY <-> staking position/uAsset` 组合为单次入口，并承接 `memeverseLauncher` genesis 集成 | `owner` 可更新 `memeverseLauncher`；调用者负责提供输入资产与授权；router 本身不承担独立资金池角色 | `IStandardizedYield`、`IOutrunStakeManager`、`IMemeverseLauncher`、`TokenHelper` | `src/router/OutrunRouter.sol`；`test/router/OutrunRouter.t.sol`；`test/router/OutrunRouterFuzz.t.sol` | 已实现且关键路由路径有测试，已证明 caller-funded pull 模式、wrap 路径、mock `genesisBySY` 的锁仓路径，以及 `genesisByToken` 的直接 fuzz 覆盖 |
| `SYBase` | 定义统一 SY 份额层抽象，提供 `deposit/redeem/preview/exchangeRate`、token 合法性检查和重入保护 | `owner` 继承自底层 pausable/ownable 资产；用户通过统一入口申赎份额 | `OutrunERC20Pausable`、`TokenHelper`、`IStandardizedYield` | `src/yield/SYBase.sol`；`test/yield/SYBaseDeposit.t.sol` | 已实现且基础输入守卫与 redeem 重入保护有测试 |
| `Aave` adapter family | 将 Aave aToken 与 underlying 封装为 SY，并以 normalized income 计算汇率与份额兑换 | 主要由用户申赎；owner 仅在部署时配置 | `OutrunAaveV3SY`、`IAaveV3Pool`、`IAToken`、`AaveAdapterLib` | `src/yield/adapters/aave/OutrunAaveV3SY.sol`；`test/yield/OutrunAaveV3SY.t.sol`；`script/deploy/YieldDeployScript.s.sol` | 已实现；存在专门测试验证 `previewRedeem` 与 `redeem` 对齐；Aave 池实际利率与资产可用性属于外部依赖边界 |
| `EtherFi` adapter family | 将 native ETH / `eETH` / `weETH` 统一为 SY，并以 liquidity pool share 汇率折算 | 用户申赎；owner 仅在部署时配置地址 | `OutrunWeETHSY`、`IDepositAdapter`、`ILiquidityPool`、`IWeETH` | `src/yield/adapters/etherfi/OutrunWeETHSY.sol`；`test/yield/OutrunWeETHSY.t.sol` | 已实现；本地测试直接覆盖 `deposit(eETH)` 后的 wrap 路径，更多 native ETH 入口与兑换正确性仍依赖 EtherFi 外部组件 |
| `Lido` adapter family | 将 Lido L1/L2 的 `stETH/wstETH` 包装成 SY，并在部分 L2 版本中支持 wrap/unwrap 或 oracle 汇率读取 | 用户申赎；owner 仅在部署或构造时配置依赖地址 | `OutrunWstETHSY`、`OutrunL2WstETHSY`、`OutrunL2WrappableWstETHSY`、`IStETH`、`IWstETH`、`IL2StETH`、`IExchangeRateOracle` | `src/yield/adapters/lido/OutrunWstETHSY.sol`；`src/yield/adapters/lido/OutrunL2WstETHSY.sol`；`src/yield/adapters/lido/OutrunL2WrappableWstETHSY.sol`；`test/yield/OutrunWstETHSY.t.sol`；`test/yield/OutrunL2WrappableWstETHSY.t.sol` | 已实现；L1 native deposit 与 L2 wrappable 路径有测试；Lido 合约与 oracle 返回值正确性属于本地依赖边界 |
| `Sky` adapter family | 将 `USDS/sUSDS` 或 L2 `USDC/USDS/sUSDS` 路径统一为 SY，并通过 ERC4626 或 PSM3 折算 | 用户申赎；owner 仅在部署或构造时配置依赖地址 | `OutrunStakedUsdsSY`、`OutrunL2StakedUsdsSY`、`IERC4626`、`IPSM3` | `src/yield/adapters/sky/OutrunStakedUsdsSY.sol`；`src/yield/adapters/sky/OutrunL2StakedUsdsSY.sol` | 已实现；当前未见专门适配器测试文件，ERC4626/PSM3 报价与结算属于外部依赖边界 |
| `Ethena` adapter family | 将 `USDe/sUSDe` 包装为 SY，并通过 ERC4626 vault 份额接口给出汇率与 deposit 路径 | 用户申赎；owner 仅在部署时配置 | `OutrunStakedUSDeSY`、`IERC4626` | `src/yield/adapters/ethena/OutrunStakedUSDeSY.sol`；`script/deploy/YieldDeployScript.s.sol` | 已实现；当前未见专门适配器测试文件，vault 资产换算与可赎回性属于外部依赖边界 |
| `L2 oracle-backed adapters` | 泛型 L2 基类，通过 oracle 读取 exchangeRate，实现 1:1 的 deposit/redeem | 用户申赎；oracle 提供者不是仓库内角色，只是外部依赖 | `OutrunL2StakedTokenSY`、`IExchangeRateOracle` | `src/yield/OutrunL2StakedTokenSY.sol` | 已实现；exchangeRate 完全来自外部 oracle，本地只做调用与归一化 |
| `Sky L2 PSM3 adapter` | Sky L2 专用 adapter，通过 PSM3 `swapExactIn` 实现多资产入金与赎回，exchangeRate 来自 `previewSwapExactIn` | 用户申赎；PSM3 地址由构造时配置 | `OutrunL2StakedUsdsSY`、`IPSM3` | `src/yield/adapters/sky/OutrunL2StakedUsdsSY.sol` | 已实现；当前未见专门适配器测试文件，PSM3 报价与结算属于外部依赖边界 |
| `L2 wrappable wstETH adapter` | Lido L2 wrappable wstETH adapter，支持 wrap/unwrap 并通过 oracle 读取汇率 | 用户申赎；oracle 提供者不是仓库内角色 | `OutrunL2WrappableWstETHSY`、`IExchangeRateOracle` | `src/yield/adapters/lido/OutrunL2WrappableWstETHSY.sol`；`test/yield/OutrunL2WrappableWstETHSY.t.sol` | 已实现且有测试；L2 汇率本身来自外部 oracle，仓库只证明调用与归一化逻辑 |
| `OutrunExchangeOracleAdapter` | 把聚合器 `latestAnswer` 标准化为 `IExchangeRateOracle.getExchangeRate()` 输出，并拒绝非正值 | 无仓库内业务角色写权限；构造后参数不可变，调用方为各 L2 adapter | `AggregatorInterface`、`IExchangeRateOracle` | `src/libraries/oracle/OutrunExchangeOracleAdapter.sol`；`test/support/MockOracleWarnings.t.sol` | 已实现；本地逻辑只保证 answer 正值检查与 decimals 归一化，底层 oracle 数据真实性属于外部依赖边界 |
| `deployment scripts` | 提供当前仓库的部署与接入入口，连接 `uAsset`、router、SY、position、mock、跨链 peer 与 CREATE3 deployer | 依赖环境变量提供 `owner/keeper/revenuePool/launcher/endpoints` 等配置；`OutrunDeployer` 为 owner-only | `OutstakeScript.s.sol`、`YieldDeployScript.s.sol`、`OutrunDeployer.sol`、测试 support 合约 | `script/deploy/OutstakeScript.s.sol`；`script/deploy/YieldDeployScript.s.sol`；`script/deploy/deployment/OutrunDeployer.sol` | 已实现；脚本表明当前仓库具备部署入口，但脚本中含注释分支，不能据此推导某链上实例已实际部署或已完成配置 |

## Test / Process Mapping Status

当前测试证据主要集中在 `test/assets`、`test/position`、`test/router`、`test/yield`。从本地文件看，`OutrunUniversalAssets`、`OutrunStakingPosition`、`OutrunRouter`、`SYBase`、Aave 适配器、部分 Lido/EtherFi/L2 wrappable 路径已有直接测试；Sky、Ethena 适配器当前更多停留在源码实现面，未在本仓库内看到同等粒度的专门测试文件。

当前 Harness 证据来自 `README.md`、`.harness/policy.json` 与 `script/harness/gate.sh`。仓库当前统一入口为 `npm run gate:fast`、`npm run gate`、`npm run gate:ci`；它们按 policy 选择 changed files、writer/reviewer 角色、verification profile 与 run-record 输出。`docs/spec/**` 的真实性仍主要依赖源码与测试可回溯性，而不是单独文档脚本赋予的通过状态。
