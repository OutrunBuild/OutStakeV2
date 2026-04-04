# OutStakeV2 Protocol Specification

## 文档目的与来源边界

本文档用于说明 `OutStakeV2` 仓库当前已经落地的协议目标、模块边界、用户可见流程与实现提醒，供阅读源码前建立统一认知。

本文档只依据本仓库的本地真源编写，包括 `README.md`、`foundry.toml`、`src/**`、`test/**`、`script/deploy/**`。未被本地实现或测试直接证明的外部协议行为，不在本文档中作为既成事实陈述，只作为本地依赖或实现假设说明。

本文档不包含 roadmap、未来设计、迁移历史，也不将 `docs/superpowers/**` 中的设计稿升级为当前规则。

## 系统目标

`OutStakeV2` 当前实现的是一套以 Foundry 为主的链上资产与收益接入表面，核心目标可归纳为以下几项：

1. 以 `uAsset` 作为统一债务与流通资产层，允许受控 minter 在额度内铸造，并通过 `repay` 路径回收已铸造额度。
2. 以 `SY` 作为标准化收益份额层，把不同外部收益资产包装为统一的 `deposit / redeem / preview / exchangeRate` 接口。
3. 以 `OutrunStakingPosition` 作为仓位账本，支持锁仓仓位、追加可提取债务、到期赎回、keeper 代偿赎回，以及公共 `wrap stake` 池。
4. 以 `OutrunRouter` 作为用户入口，把 `token <-> SY <-> position/uAsset` 的组合路径收敛为单次调用，并保留一个面向 `memeverseLauncher` 的 genesis 集成入口。
5. 通过 `script/deploy/**` 提供当前存在的部署与接入脚本，把不同链上的 `uAsset`、`SY`、`position` 和相关参数连接起来。

## 当前范围

### assets

当前资产层以 [`src/assets/base/OutrunUniversalAssets.sol`](../../src/assets/base/OutrunUniversalAssets.sol) 为中心。该合约维护按 minter 维度记录的 `mintingCap` 与 `amountInMinted`，只允许在剩余额度内铸造 `uAsset`，并要求通过 `repay(account, amount)` 由 minter 自身回收对应债务。测试还证明该资产保留 flash mint / flash loan 能力，并允许 owner 设置 flash fee 接收方。

资产层还包含 [`src/assets/omnichain/OutrunOFT.sol`](../../src/assets/omnichain/OutrunOFT.sol) 的 OFT 扩展表面，因此本地实现具备跨链消息接口与本地铸烧逻辑。但跨链消息是否成功送达、对端 peer 配置是否正确、LayerZero 端点如何结算，属于外部系统依赖，不在本文档中作为本地已证事实。

### position

当前仓位层由 [`src/position/OutrunStakingPosition.sol`](../../src/position/OutrunStakingPosition.sol) 实现，维护 `positions`、`syTotalStaking`、`syWrapStaking`、`wrapUAssetDebt`、`minStake`、`keeper`、`revenuePool` 等状态。该层区分两类账本：

- 锁仓仓位：每个 `positionId` 记录 owner、SY 本金、已铸造 `uAsset` 债务、开始时间和到期时间。
- 公共 wrap 池：不按用户单独建仓，而是汇总记录池内 SY 本金和对应 `uAsset` 债务。

锁仓仓位按当前 `exchangeRate` 折算可铸造价值；到期后可按赎回比例销毁 `uAsset` 并取回 `SY` 或 `tokenOut`。wrap 池维持“按债务兑回 SY”的主池语义，超出债务等值部分的收益只能由 owner 通过 `harvestWrapYield` 提取到 `revenuePool`。

### yield

当前收益层以 [`src/yield/SYBase.sol`](../../src/yield/SYBase.sol) 为统一抽象。每个 SY 适配器都需要实现：

- `deposit` / `redeem`
- `previewDeposit` / `previewRedeem`
- `exchangeRate`
- `getTokensIn` / `getTokensOut`
- `isValidTokenIn` / `isValidTokenOut`

本地已存在 Aave、Lido、Etherfi、Lista、Sky、Ethena 等适配器源码表面；它们共享统一份额语义，但具体兑换、利息来源和底层状态仍依赖外部协议。就本地代码而言，协议只承诺”调用对应适配器并使用其 `exchangeRate` / redeem / deposit 结果完成账务”。

### Ethena redeem 限制

Ethena adapter（`OutrunStakedUSDeSY`）的 `getTokensOut()` 只返回 `sUSDe` 本身，`_redeem()` 实现也始终输出 `yieldBearingToken`（即 sUSDe）。这意味着通过该 adapter redeem 时，用户只能拿回 sUSDe，不能直接回到 USDe。这是 Ethena vault 的产品级限制。

### router

当前路由层由 [`src/router/OutrunRouter.sol`](../../src/router/OutrunRouter.sol) 实现。它不维护独立资金池，而是采用 caller-funded pull 模式：

- 用户先授权给 router。
- router 从调用者拉取 `tokenIn`、`SY` 或 `uAsset`。
- router 再调用 SY 或 staking position 完成组合操作。

router 当前覆盖 `mintSYFromToken`、`redeemSyToToken`、`stakeFromToken`、`stakeFromSY`、`wrapStakeFromToken`、`wrapStakeFromSY`、`wrapRedeem`、若干 preview 接口，以及 `genesisByToken` / `genesisBySY`。

### integrations

当前集成层存在于 `src/integrations/**` 与部分 `src/libraries/oracle/**`。本地代码为 Aave、Lido、Etherfi、Lista、Sky 等协议提供接口与适配依赖，也提供 oracle adapter 表面。但这些外部系统的真实结算、价格更新、队列、权限和可用性，不由本仓库单独证明；本文档仅将其视为本地合约调用时依赖的外部前提。

### deployment

当前部署层以 [`script/deploy/OutstakeScript.s.sol`](../../script/deploy/OutstakeScript.s.sol)、[`script/deploy/YieldDeployScript.s.sol`](../../script/deploy/YieldDeployScript.s.sol) 和 [`script/deploy/deployment/OutrunDeployer.sol`](../../script/deploy/deployment/OutrunDeployer.sol) 为主。

本地脚本显示当前部署模式依赖环境变量注入 owner、keeper、revenuePool、router、launcher、外部协议地址与 endpoint 配置。`OutrunDeployer` 提供 owner-only 的 CREATE3 部署能力。脚本中存在多条被注释的可选步骤，因此本文档只把这些脚本视为“当前仓库提供的部署入口”，不把其中未执行的链上状态视为已部署事实。

### tests

测试范围分布在 `test/assets`、`test/position`、`test/router`、`test/yield`、`test/support`。现有测试直接证明了以下现状：

- `uAsset` 的 mint cap、repay、flash fee 接收方与 OFT 溢出保护。
- staking position 的建仓、补提债务、到期赎回、keeper 代偿赎回、wrap stake、wrap redeem、收益 harvest。
- router 的 pull 模式、native/erc20 输入约束、wrap 路径、genesis 路径和最小 `uAsset` 输出保护。
- `SYBase` 的 native/erc20 输入守卫与 redeem 重入保护。
- 部分适配器的关键兑换路径与 preview 对齐关系。

## 用户可见主流程

### 1. 把基础资产转换为 SY

用户可以直接调用某个 SY 的 `deposit`，或通过 router 的 `mintSYFromToken` / `stakeFromToken` / `wrapStakeFromToken` 间接完成。当前实现要求输入资产由调用者提供，router 不消费其预置余额来代替用户出资。

### 2. 以 SY 建立锁仓仓位并获得 uAsset

用户可以直接调用 `OutrunStakingPosition.stake`，也可以通过 router 的 `stakeFromToken` 或 `stakeFromSY` 进入。建仓时会：

- 拉取用户的 SY；
- 按当前 `exchangeRate` 折算本金价值；
- 为新仓位记录 owner、锁仓截止时间与已铸造债务；
- 由 position 合约作为 minter 向指定接收者铸造等值 `uAsset`。

仓位 owner 与 `uAsset` 接收者可以是不同地址，这是当前实现允许的显式行为。

Router 层通过 `StakeParam` 结构体暴露了此能力：

- `StakeParam.owner`：position owner，拥有仓位控制权（draw、redeem 等）
- `StakeParam.receiver`：uAsset 接收地址，当 `receiver == address(0)` 时回退到 `owner`

genesis 流程不使用 `StakeParam`，而是将 uAsset mint 给 router 自己，再由 router 授权并转给 `memeverseLauncher`。

### 3. 在仓位升值后追加提取 uAsset

若 `SY.exchangeRate()` 上升，position owner 可以调用 `drawUAsset`，只提取“当前仓位价值减去已铸造债务”的增量部分。该流程不会增加 SY 本金，只会增加该仓位对应的 `uAsset` 债务。

### 4. 到期后赎回锁仓仓位

到期前仓位不能赎回。到期后，position owner 可以按任意 `syRedeemed` 比例赎回仓位；系统会按相同比例计算应销毁的 `uAsset`，要求调用者先授权 position 合约销毁该 `uAsset`，再把对应的 `SY` 或 `tokenOut` 发给接收者。

如果 `tokenOut != SY`，实际输出数量取决于目标 SY 适配器的 redeem 结果，因此属于“本地调用适配器后的输出”，而不是本仓库单独定义的固定兑换规则。

### 5. 使用 keeper 代偿到期仓位

owner 可设置单一 `keeper`。keeper 可以在仓位到期后调用 `keepRedeem`，使用自己提供并授权的 `uAsset` 代偿部分债务。当前实现下：

- keeper 先销毁自己提供的 `uAsset`；
- 协议按仓位债务比例计算对应可赎回 SY；
- keeper 优先取回与其代偿 `uAsset` 等值的 SY 本金；
- 若该比例下存在额外 SY，则返还给仓位 owner；
- 当前实现没有在该路径上额外收取协议手续费。

### 6. 使用 wrap stake 公共池

用户可以通过 `wrapStake`、`wrapStakeFromToken`、`wrapStakeFromSY` 把 SY 记入公共 wrap 池，并立即获得等值 `uAsset`。wrap 池不建立独立 `positionId`，而是维护全池 `syWrapStaking` 与 `wrapUAssetDebt`。

wrap 池赎回时，用户需要销毁自己的 `uAsset`，协议按当前 `exchangeRate` 折算应返还的 SY 数量。若汇率下跌导致债务等值 SY 超过池内 SY，本地实现会直接拒绝超额兑回。

### 7. 提取 wrap 池超额收益

当 wrap 池中的 SY 余额高于 `wrapUAssetDebt` 折算出来的等值 SY 时，owner 可以调用 `harvestWrapYield` 把超额部分发送到 `revenuePool`。这代表当前实现把 wrap 池收益视为协议可收取的收入，而不是自动归属于任意单个 wrap 用户。

### 8. 通过 router 进入 genesis 集成

router 提供 `genesisByToken` 与 `genesisBySY`。当前实现不是把用户资金放入 wrap 池，而是先创建一个锁仓仓位，再把新铸造的 `uAsset` 授权并交给 `memeverseLauncher.genesis(...)`。`memeverseLauncher` 地址可由 router owner 修改，因此该入口属于当前存在的可配置外部集成点。

## 非目标

当前实现未在本地代码中承诺以下事项，故不属于本文档范围：

1. 不定义外部协议自身的收益来源、清算机制、升级规则或权限规则。
2. 不保证任何链、任何 endpoint、任何 launcher 地址当前已经完成部署或可用。
3. 不定义前端、索引器、keeper 运维、报价服务或跨链 relayer 的离线流程。
4. 不提供独立的协议治理模块；当前可见管理能力主要来自 owner 与 keeper 配置。
5. 不把未在源码和测试中出现的产品模块、费用模型或用户权利写入正式规则。

## 当前实现提醒

1. `uAsset` 不是任意自由铸造资产；每个 minter 都受 `mintingCap` 约束，position 合约能否继续铸造取决于 owner 事先授予的额度。
2. router 当前明确是 pull 模式。测试证明它不会主动消耗 router 已预置的同类资产来代替调用者出资。
3. position 的赎回、wrap 赎回与 keeper 代偿都要求先授权 `uAsset` 给 position 或 router，再由下游合约执行 `repay`。
4. 锁仓仓位和 wrap 池采用不同收益归属逻辑：仓位升值可由 owner 通过 `drawUAsset` 体现为新增债务；wrap 池超额收益则可由 owner 提取到 `revenuePool`。
5. 当前多个 SY 适配器依赖外部协议接口、汇率函数或包装器合约；本仓库只证明“本地如何调用它们”，不单独证明这些外部组件必然按预期工作。
6. `OutrunRouter` 仍保留 owner 可修改 `memeverseLauncher` 的维护入口，源码中也存在注释表明该控制面具有预发布性质；因此该集成地址不应被视为不可变协议常量。
