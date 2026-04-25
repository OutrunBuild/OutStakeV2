# OutStakeV2 架构总览

## 1. 模块地图

### 1.1 资产层

- `src/assets/base/OutrunERC20.sol`
- `src/assets/base/OutrunERC20Pausable.sol`
- `src/assets/base/OutrunUniversalAssets.sol`
- `src/assets/omnichain/OutrunOFT.sol`
- `src/assets/interfaces/IUniversalAssets.sol`
- uAsset 统一债务与流通资产层，维护按 minter 维度的 mint cap / 已铸造债务 / mint / repay 路径，并继承 ERC20 / pause / OFT 跨链铸烧能力。

### 1.2 仓位层

- `src/position/OutrunStakingPosition.sol`
- `src/position/interfaces/IOutrunStakeManager.sol`
- 管理锁仓仓位、可追加 uAsset 债务、到期赎回、keeper 代偿赎回、公共 wrap 池与 wrap 收益 harvest。

### 1.3 收益层

- `src/yield/SYBase.sol`
- `src/yield/adapters/aave/OutrunAaveV3SY.sol`
- `src/yield/adapters/ethena/OutrunStakedUSDeSY.sol`
- `src/yield/adapters/etherfi/OutrunWeETHSY.sol`
- `src/yield/adapters/lido/OutrunWstETHSY.sol`
- `src/yield/adapters/lido/OutrunL2WstETHSY.sol`
- `src/yield/adapters/lido/OutrunL2WrappableWstETHSY.sol`
- `src/yield/adapters/sky/OutrunStakedUsdsSY.sol`
- `src/yield/adapters/sky/OutrunL2StakedUsdsSY.sol`
- `src/yield/OutrunL2StakedTokenSY.sol`
- `src/yield/interfaces/IStandardizedYield.sol`
- SY 份额层抽象，把外部收益资产包装为统一的 deposit / redeem / preview / exchangeRate 接口。

### 1.4 路由层

- `src/router/OutrunRouter.sol`
- `src/router/interfaces/IOutrunRouter.sol`
- `src/router/interfaces/IMemeverseLauncher.sol`
- 把 token <-> SY <-> staking position/uAsset 组合为单次入口，并承载 memeverseLauncher genesis 集成。

### 1.5 集成与 Oracle 层

- `src/integrations/{aave,etherfi,lido,sky}/interfaces/*.sol`
- `src/libraries/oracle/OutrunExchangeOracleAdapter.sol`
- 外部协议最小 interface 与 adapter 调用封装；oracle adapter 作为薄层标准化精度归一化。

### 1.6 底层库

- `src/libraries/TokenHelper.sol`
- `src/libraries/SYUtils.sol`
- `src/libraries/ReentrancyGuard.sol`
- `src/libraries/AaveAdapterLib.sol`
- `src/libraries/ArrayLib.sol`
- `src/libraries/AutoIncrementId.sol`
- `src/libraries/CommonErrors.sol`
- `src/libraries/IWETH.sol`
- `src/libraries/WadRayMath.sol`
- 跨业务域共享的 token 传输、汇率换算、重入保护、数组操作、ID 生成、错误定义等基础工具。

## 2. 关键资金流

### 2.1 Token / Native -> SY

用户授权 router -> router 从调用者拉取 tokenIn -> 调用 SY.deposit() -> SY 份额 mint 给 receiver。

### 2.2 SY -> Token

调用者把 SY 转入 SY 合约地址 -> 调用 SY.redeem() -> 份额从合约自身余额 burn -> 目标 token 转给 receiver。

### 2.3 Token / SY -> Locked Stake

用户授权 -> router 调用 SY 转换 -> position.stake() -> 拉取 SY -> 按 exchangeRate 折算 principalValue -> 写入 position -> uAsset.mint(uAssetReceiver, principalValue)。

### 2.4 Token / SY -> Wrap Stake

用户授权 -> SY 转换 -> position.wrapStake() -> 拉取 SY -> 按 exchangeRate 折算 -> 增加 syTotalStaking / syWrapStaking / wrapUAssetDebt -> uAsset.mint(uAssetRecipient, principalValue)。

### 2.5 Wrap Redeem

调用者授权 uAsset -> router 代收 uAsset -> position.wrapRedeem() -> uAsset.repay() burn debt -> 按 exchangeRate 换算 SY -> 减少池账务 -> 输出 SY 或目标 token 给 receiver。

### 2.6 Position Redeem (到期)

position owner 授权 uAsset -> position.redeem() -> 按比例计算 UAssetBurned -> uAsset.repay() burn -> 减少 position.syStaked 与 position.UAssetMinted -> 输出 SY 或目标 token。

### 2.7 Keeper Redeem

keeper 授权 uAsset -> position.keepRedeem() -> keeper 的 uAsset burnt -> 按 keeperPrincipalSY 与 syRedeemed 分账 -> keeper 收 principal，owner 收 excess。

### 2.8 Harvest Wrap Yield

owner 调用 harvestWrapYield -> 计算 wrap 池盈余 (syWrapStaking > assetToSy(wrapUAssetDebt)) -> 减少 syTotalStaking / syWrapStaking -> 盈余转 revenuePool。

### 2.9 Genesis

用户入金 -> router 创建 locked position -> uAsset mint 给 router -> router 授权并调用 memeverseLauncher.genesis() -> launcher 拉走 uAsset。

## 3. 系统架构图

### 3.1 合约依赖树

方向: `→` 表示"依赖 / 调用"，`⟶` 表示"extends(继承)"。

#### uAsset 继承链

```
OutrunUniversalAssets (concrete)
  ⟶ OutrunOFT (abstract)
    ⟶ OFTCore                          ← @layerzerolabs/oft-evm
    ⟶ RateLimiter                      ← @layerzerolabs/oapp-evm
    ⟶ OutrunERC20Pausable
      ⟶ OutrunERC20
```

#### Position 继承链

```
OutrunStakingPosition (concrete)
  ⟶ Ownable                            ← openzeppelin
  ⟶ Pausable                           ← openzeppelin
  ⟶ IOutrunStakeManager (interface)
  依赖:
    → OutrunUniversalAssets (uAsset)     mint / repay
    → IStandardizedYield (SY)            exchangeRate / redeem
    → TokenHelper, SYUtils, ArrayLib,
      AutoIncrementId, CommonErrors
```

#### Router 依赖扇出

```
OutrunRouter (concrete)
  ⟶ IOutrunRouter (interface)
  ⟶ Ownable                            ← openzeppelin
  依赖:
    → IStandardizedYield               deposit / redeem / preview*
    → IOutrunStakeManager              stake / wrapStake / wrapRedeem / preview*
    → IMemeverseLauncher               genesis
    → TokenHelper, CommonErrors
```

#### SY Adapter 统一结构

```
Concrete Adapter (e.g. OutrunAaveV3SY)
  ⟶ SYBase (abstract)
    ⟶ OutrunERC20Pausable
      ⟶ OutrunERC20
    ⟶ IStandardizedYield (interface)
    → TokenHelper, ReentrancyGuard, CommonErrors

Concrete Adapter (e.g. OutrunL2WstETHSY)
  依赖:
    → IExchangeRateOracle              getExchangeRate()

OutrunExchangeOracleAdapter
  → AggregatorInterface                latestAnswer()
  → IExchangeRateOracle
```

### 3.2 全局调用关系图

#### 3.2.1 合约调用关系

```
  User (EOA / ECA)
  approve(router / position / SY, ...)
       │
   ├────┬────────────┬────────────────┐
   ▼    ▼            ▼                ▼
+--------+  +--------------+  +-------------+  +------------------+
| Router |  | SYBase +     |  | Outrun      |  | IMemeverse       |
|        |  | Adapters     |  | StakingPos  |  | Launcher         |
|        |  |              |  |             |  | (external)       |
|mintSY  |  | deposit      |  | stake       |  |                  |
|redeemSy|  | redeem       |  | drawUAsset  |  | genesis          |
|stake   |  | preview*     |  | redeem      |  └────────┬─────────┘
|wrapStk |  | exchangeRate |  | wrapStake   |           │
|wrapRdm |  └──────┬───────┘  │ wrapRedeem  │  ┌────────┴─────────┐
|genesis │         │          │ keepRedeem  │  | SY token via     |
+───┬────┘         │     ┌────┤ harvest     │  | wrapRedeem       |
    │              │     │    │ preview*    │  | ·redeem          |
    └──────────────┘     │    └─────┬─┬─────┘  └────────┬─────────┘
                         │          │ │                 │
                 deposit/redeem mint│ │repay            │
                                    │ │             ┌───┘
                                    ▼ ▼             ▼
                          +----------------┐  +────────────┐
                          | OutrunUniversal|  | SY token   |
                          | Assets (uAsset)|  | ·redeem    |
                          |                |  └────────────┘
                          | ·mint          |
                          |   (minter cap) ├──────► OutrunOFT
                          | ·repay         |             │
                          └────────────────┘      _debit / _credit
                                                         │
                                               LayerZero Endpoint (external)
```

#### 3.2.2 调用关系说明

| Caller | Callee | 入口 |
| --- | --- | --- |
| Router | SY | `mintSYFromToken` → `SY.deposit`；`redeemSyToToken` → `SY.redeem` |
| Router | Position | `stakeFromToken`/`stakeFromSY` → `stake`/`wrapStake`；`wrapRedeem` → `position.wrapRedeem` |
| Router | Launcher | `genesisByToken`/`genesisBySY` → `launcher.genesis` |
| Position | uAsset | `stake`/`wrapStake` → `mint`；`redeem`/`keepRedeem` → `repay` |
| Adapter | External Protocol | deposit → `supply`/`wrap`/`deposit`；redeem → `withdraw`/`unwrap`/`release` |
| OutrunOFT | LayerZero | `_toSD` 编码消息；`_debit` burn 本链；`_credit` mint 远端 |

### 3.3 资金流方向

方向标注: `token/token → SY` 表示资金从调用者流入 SY。

```
入金路径 (资金流向协议):

  User tokenIn  ──approve──► Router ──transferFrom──► Router
                                                         │
                                                    deposit
                                                         ▼
  User tokenIn  ──approve──► Adapter/SY ──transferFrom──► Adapter
                                                         │
                                                   deposit → external supply
                                                         │
                                                    mint SY shares
                                                         ▼
                                                   User receives SY

锁定 Stake (资金从 SY → uAsset):

  SY ──transferFrom──► Position ──exchangeRate──► principalValue
                                                        │
                                                   mint uAsset
                                                        ▼
                                                 uAssetReceiver receives uAsset

Wrap Stake (资金进入共享池):

  SY ──transferFrom──► Position
    → syTotalStaking  += amountInSY
    → syWrapStaking   += amountInSY
    → wrapUAssetDebt  += principalValue
    → mint uAsset to uAssetRecipient

赎回路径 (资金流出协议):

  User uAsset ──approve──► Position ──repay(burn)──► Position
    → reduce position.syStaked / UAssetMinted
    → transfer SY or external redeem → token to receiver

  User uAsset ──approve──► Position ──repay(burn)──► Position (wrapRedeem)
    → reduce syTotalStaking / syWrapStaking / wrapUAssetDebt
    → transfer SY or external redeem → token to receiver

Keeper 代偿:

  Keeper uAsset ──approve──► Position ──repay(burn)
    → keeperPrincipalSY → keeper (receiver)
    → ownerExcessSY     → position owner

Harvest:

  Position syWrapStaking (surplus) ──► revenuePool
```

### 3.4 设计约束

- Router **不承担**独立资金池角色，所有资金来自调用者（caller-funded pull 模式）。
- 用户也**可直接调用** SY.deposit/redeem 与 Position.stake/wrapStake/wrapRedeem，无需经过 Router。
- uAsset.mint 是公开函数，但受 owner 配置的 mintingCap 约束，不是任何人都能铸造。
- Position 合约本身必须先在 uAsset 上被授予 mintingCap，才能继续铸造。

## 4. 文档分层（Doc Layering）

当前文档系统按四层组织：

1. Harness Contract 层
   - `AGENTS.md`
   - `CLAUDE.md`
   - `.harness/policy.json`
   - `script/harness/gate.sh`
   - `README.md`
   - `.github/workflows/test.yml`
   - `.githooks/*`
   - `.claude/settings.json`
2. Product Truth 层（当前规则真源）
   - `docs/spec/protocol.md`（系统目标与模块边界）
   - `docs/spec/router/router-and-user-flows.md`（完整路由路径分析）
   - `docs/spec/position/state-machines.md`（状态机）
   - `docs/spec/position/accounting.md`（账务规则）
   - `docs/spec/access-control.md`（权限边界）
   - `docs/spec/yield/yield-adapters.md`（adapter 行为与缺口）
   - `docs/spec/yield/oracles-and-integrations.md`（外部集成边界）
   - `docs/spec/common-foundations.md`（library 基础语义）
   - `docs/deployment.md`（部署入口与环境变量）
   - `docs/implementation-map.md`（surface 表格索引）
   - `docs/testing-and-evidence.md`（测试分层与证据强度）
   - `docs/ARCHITECTURE.md`（本文件：系统级模块地图）
   - `docs/GLOSSARY.md`（术语表）
   - `docs/TRACEABILITY.md`（规则到证据追溯）
   - `docs/VERIFICATION.md`（验证入口指南）
   - `docs/SECURITY_AND_APPROVALS.md`（安全审阅规则）
3. Implementation Evidence 层（规则落地证据）
   - `src/**`
   - `test/**`
4. Topic Guides 层（设计稿与计划工件，不是当前规则真源）
   - `docs/superpowers/specs/*`
   - `docs/superpowers/plans/*`

冲突处理顺序：

- 当前规则判断以 Product Truth 层为准，并用 Implementation Evidence 层核验。
- Topic Guides 层用于补充设计历史，不单独定义当前规则。
- 若 `docs/spec/*.md` 与 `src/**` 冲突，以 `src/**` 为准。

## 5. 推荐阅读顺序

1. `CLAUDE.md`（仓库流程与角色约定，5 分钟）
2. `docs/ARCHITECTURE.md`（本文件，先建立层次与边界，5 分钟）
3. `docs/GLOSSARY.md`（术语定义基线，3 分钟）
4. `docs/spec/protocol.md`（系统目标与 8 条用户可见流程，8 分钟）
5. `docs/spec/position/state-machines.md`（7 个状态机，8 分钟）
6. `docs/spec/position/accounting.md`（4 层账务规则，8 分钟）
7. `docs/spec/access-control.md`（权限边界清单，5 分钟）
8. `docs/spec/router/router-and-user-flows.md`（完整路由路径与边界，10 分钟）
9. `docs/spec/yield/yield-adapters.md`（8 组 adapter 实现与缺口，10 分钟）
10. `docs/TRACEABILITY.md` + `docs/VERIFICATION.md`（证据追溯与验证路径）

## 6. 当前已知边界提醒

- uAsset 按 minter 独立记账，不是全局总债务池。
- Router 当前是 pull 模式，不会消费 pre-funded 余额代替调用者出资。
- Genesis 当前走的是 locked stake 路径，不是 wrap stake 路径。
- Wrap 池按 principal debt 记账，不会因为汇率上涨自动给用户补发更多 uAsset。
- 多个 SY adapter 的 deposit/redeem 核心路径缺少独立测试，当前更多依赖源码表面证据。
- Oracle adapter 是薄层精度归一化器，不实现 freshness check、deviation bounds 或 fallback。
- 跨链 OFT 消息传递的正确性依赖 LayerZero 端点与 peer 配置，不属于本地仓库可直接证明的事实。
