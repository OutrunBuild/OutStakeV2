# OutStakeV2 Router And User Flows

## 1. 文档目的

本文档整理 `OutrunRouter`、`OutrunStakingPosition` 与 `SYBase` 当前已经实现的用户流程，覆盖 token / native、`SY`、locked stake、wrap stake、wrap redeem、genesis 与 preview 语义。本文只记录本地代码和现有测试能直接证明的行为，并记录当前 router 与 proxy-backed products 的边界。

## 1.1 Upgradeable readiness

当前 upgradeable product surface 不把 `OutrunRouter` 部署为 proxy：

- router 仍是非 upgradeable、可重部署 helper。
- router 业务入口仍通过用户传入的独立 `SY` 地址、`SP` 地址或从 `SP.SY()` 派生的 canonical `SY` 调用下游。
- 下游 product address 可以是 `ERC1967Proxy` 地址：uAsset proxy、SY proxy、staking position proxy。
- router 本身不持有 core accounting state；切换 router 需要用户/集成侧重新授权或改用新入口，但不迁移 position、uAsset debt 或 SY share state。
- router 不获得 upgrade admin、timelock、pause、allowlist 或 oracle 管理能力。

## 2. token / native -> SY

`mintSYFromToken(SY, tokenIn, receiver, amountInput, minSyOut)` 是 router 的 token 或 native 入金入口。

- router 先校验：如果 `tokenIn != NATIVE`，则 `msg.value` 必须为 0，否则回退 `NativeAmountMismatch()`。
- router 总是从 `msg.sender` 拉取 `tokenIn`，不会消费 router 自己预存的同名余额。测试也证明 router 即使事先有 prefund，实际入金仍来自调用者。
- 之后 router 调用 `IStandardizedYield(SY).deposit(receiver, tokenIn, amountInput, minSyOut)`。
- `SYBase.deposit(...)` 会再次校验：
  - `tokenIn` 必须是 `isValidTokenIn(tokenIn)` 支持的资产。
  - `amountTokenToDeposit` 不能为 0。
  - 若 `tokenIn != NATIVE`，`msg.value` 也必须为 0。
- `SYBase.deposit(...)` 成功后，`SY` 份额直接 mint 给 `receiver`，不是留在 router。
- native 路径下，router 会把 `amountInput` 作为 `value` 传给 `SY.deposit(...)`；测试证明这一路径会把 `tokenIn` 记录为 `address(0)`，并把相同数额的 `msg.value` 透传给 `SY`。

## 3. SY -> token

`redeemSyToToken(SY, receiver, tokenOut, amountInSY, minTokenOut)` 是 router 的 `SY` 赎回入口。

- router 会先把 `amountInSY` 从调用者转到 `SY` 合约地址本身，而不是转到 router 自己。
- 然后 router 调用 `IStandardizedYield(SY).redeem(receiver, amountInSY, tokenOut, minTokenOut, true)`。
- `burnFromInternalBalance = true` 的含义是：`SYBase.redeem(...)` 会从 `address(this)`，也就是 `SY` 合约自身余额里烧份额。
- `SYBase.redeem(...)` 会校验：
  - `tokenOut` 必须是 `isValidTokenOut(tokenOut)` 支持的资产。
  - `amountSharesToRedeem` 不能为 0。
  - 实际产出的 `amountTokenOut` 不能低于 `minTokenOut`。
- 测试证明这一路径也不会动用 `SY` 合约里已有的 prefund internal balance；调用者的 `SY` 仍然会被先转入，再按本次数量烧掉。

## 4. token -> locked stake

`stakeFromToken(SP, tokenIn, tokenAmount, stakeParam)` 当前实现是”从 `SP.SY()` 派生 canonical `SY`，先 mint `SY`，再创建 locked position”。

`StakeParam` 结构体包含以下字段：
- `lockupDays`：锁仓天数
- `minSyOut`：token -> SY 最小输出（滑点保护）
- `minUAssetMinted`：SY -> uAsset 最小输出（滑点保护）
- `owner`：position owner，拥有仓位控制权
- `receiver`：uAsset 接收地址；当 `receiver == address(0)` 时回退到 `owner`

当前路由行为：
- router 先从 `SP.SY()` 读取 stake manager 绑定的 canonical `SY`，不接收调用者单独传入的 `SY`。
- router 先调用 `_mintSY(..., address(this), tokenAmount, stakeParam.minSyOut)`，把新 mint 的 `SY` 留在 router。
- router 解析 uAsset 接收地址：`uAssetReceiver = stakeParam.receiver == address(0) ? stakeParam.owner : stakeParam.receiver`。
- 然后 router 调用 `SP.stake(amountInSY, stakeParam.lockupDays, stakeParam.owner, uAssetReceiver)`。
- `OutrunStakingPosition.stake(...)` 的行为是：
  - `positionOwner` 和 `uAssetReceiver` 不能为零地址。
  - `amountInSY` 必须满足 `minStake`。
  - 把 `SY` 从 router 拉入 position 合约。
  - 按当前 `SY.exchangeRate()` 把 `amountInSY` 折算成 `principalValue`。
  - 用这个 `principalValue` 作为初始 `UAssetMinted`。
  - 新建 `positionId`，写入 `owner`、`syStaked`、`UAssetMinted`、`startTime`、`deadline`。
  - 向 `uAssetReceiver` mint 等额 `uAsset`。
- router 在 stake 完成后才检查 `UAssetMinted >= stakeParam.minUAssetMinted`；不足时整笔交易回退并报 `InsufficientUAssetMinted(...)`。

## 5. SY -> locked stake

`stakeFromSY(SP, amountInSY, stakeParam)` 与上一路径的差别，只在于输入资产已经是 `SP.SY()` 返回的 canonical `SY`。

- router 先从 `SP.SY()` 读取 canonical `SY`，再把 `amountInSY` 从调用者拉到自己地址。
- 之后走和 `token -> locked stake` 一样的 `_stakeFromSYBalance(...)` 路径。
- router 根据 `stakeParam.receiver` 决定 uAsset 接收地址：若 `receiver == address(0)` 则回退到 `stakeParam.owner`。
- locked position 创建后的核心语义不变：
  - `deadline = block.timestamp + lockupDays * 1 days`
  - 初始 debt 由当前 `exchangeRate()` 定价，不是固定 1:1
  - position 赎回必须等到 `deadline` 到期
- 测试证明：若实际铸出的 `uAsset` 低于 `stakeParam.minUAssetMinted`，router 会整笔回退。

## 6. token / SY -> wrap stake

当前 wrap stake 走的是共享 wrap 池，不会生成 `positionId`。

### 6.1 token -> wrap stake

`wrapStakeFromToken(SP, tokenIn, tokenAmount, minSyOut, uAssetRecipient, minUAssetMinted)` 的流程是：

- router 先从 `SP.SY()` 读取 stake manager 绑定的 `SY`。
- router 调用 `_mintSY(SY, tokenIn, address(this), tokenAmount, minSyOut)`，先把 token / native 转成 `SY`，并由 `SY.deposit(...)` 校验 token -> SY 最小输出。
- router 再调用 `SP.wrapStake(amountInSY, uAssetRecipient)`。
- router 在 wrap stake 完成后校验 `UAssetMinted >= minUAssetMinted`；不足时整笔交易回退并报 `InsufficientUAssetMinted(...)`。

### 6.2 SY -> wrap stake

`wrapStakeFromSY(SP, amountInSY, uAssetRecipient, minUAssetMinted)` 的流程是：

- router 先从 `SP.SY()` 读取 canonical `SY`，再把 `SY` 从调用者拉到自己地址。
- router 再调用 `SP.wrapStake(amountInSY, uAssetRecipient)`。
- router 在 wrap stake 完成后校验 `UAssetMinted >= minUAssetMinted`；不足时整笔交易回退并报 `InsufficientUAssetMinted(...)`。

### 6.3 wrap stake 落到 position 合约后的语义

`OutrunStakingPosition.wrapStake(...)` 当前行为是：

- `amountInSY` 不能为 0，`uAssetRecipient` 不能为零地址。
- 把 `SY` 拉入 position 合约。
- 按当前 `exchangeRate()` 把 `amountInSY` 折算成 `principalValue`。
- 更新共享账务：
  - `syTotalStaking += amountInSY`
  - `syWrapStaking += amountInSY`
  - `wrapUAssetDebt += principalValue`
- 给 `uAssetRecipient` mint `principalValue` 数量的 `uAsset`。

测试证明：

- wrap stake 返回值是本次 mint 的 `uAsset` 数量。
- `wrapStakeFromSY(...)` 会直接把 `uAsset` 打给 `uAssetRecipient`。
- wrap stake 不产生独立 `positionId`。

## 7. wrap redeem

`wrapRedeem(SP, amountInUAsset, receiver, tokenOut, minTokenOut)` 是 router 的 wrap 池赎回入口。

- router 会先读取 `SP.uAsset()`，把 `amountInUAsset` 从调用者拉到 router。
- router 给 `SP` 授权后，调用 `SP.wrapRedeem(amountInUAsset, receiver, tokenOut, minTokenOut)`。
- `OutrunStakingPosition.wrapRedeem(...)` 当前行为是：
  - `receiver` 不能为零地址，`amountInUAsset` 不能为 0。
  - `amountInUAsset` 不能大于 `wrapUAssetDebt`。
  - 先按当前 `exchangeRate()` 用 `_assetToSy(...)` 把 `uAsset` 数量换算成 `amountInSY`。
  - 若 `amountInSY > syWrapStaking`，则回退 `ExceedsWrapPoolBalance(...)`。
  - position 合约对调用者执行 `uAsset.repay(msg.sender, amountInUAsset)`，也就是烧掉 router 此次代收的 `uAsset`。
  - 然后减少：
    - `syTotalStaking`
    - `syWrapStaking`
    - `wrapUAssetDebt`
  - 若 `tokenOut == SY`，直接校验 `amountInSY >= minTokenOut` 并转出 `SY`；否则把 `minTokenOut` 传给 `SY.redeem(...)`。

测试证明：

- router 的 `wrapRedeem(...)` 确实会先代收 `uAsset`，再把 `SY` 或目标 token 发给 `receiver`。
- 当 `exchangeRate` 上升时，用户赎回同样数量的 `uAsset`，拿回的 `SY` 会减少，因为 wrap 池按 principal debt 运行。
- wrap 池若升值过高，也可能出现 `amountInSY > syWrapStaking`，此时会直接回退，而不是部分成交。

## 8. genesis flows

当前 router 提供两个 genesis 入口：`genesisByToken(...)` 和 `genesisBySY(...)`。

### 8.1 genesisByToken

- `genesisByToken(SP, tokenIn, tokenAmount, minSyOut, minUAssetMinted, lockupDays, verseId, genesisUser)` 会先读取 `SP.SY()`，把 `tokenIn` 转成 `SY`，并把 `minSyOut` 传给 token -> SY deposit。
- 然后调用 `SP.stake(amountInSY, lockupDays, genesisUser, address(this))`。
- 这里走的是 locked stake，不是 wrap stake。
- stake 产出的 `uAsset` 先 mint 给 router 自己。
- router 在 stake 后校验 `amountInUAsset >= minUAssetMinted`；不足时整笔交易回退并报 `InsufficientUAssetMinted(...)`。
- router 校验 `amountInUAsset <= type(uint128).max`。
- 之后 router 授权 `memeverseLauncher`，再调用 `memeverseLauncher.genesis(verseId, uint128(amountInUAsset), genesisUser)`。

### 8.2 genesisBySY

- `genesisBySY(SP, amountInSY, lockupDays, verseId, genesisUser, minUAssetMinted)` 会先从 `SP.SY()` 读取 canonical `SY`，再从调用者拉取 `SY`。
- 后续和 `genesisByToken(...)` 一样，仍然调用 `SP.stake(...)` 创建 locked position。
- router 在 stake 后校验 `amountInUAsset >= minUAssetMinted`；不足时整笔交易回退并报 `InsufficientUAssetMinted(...)`。
- 最终也是由 launcher 拉走本次 stake 产出的 `uAsset`。

### 8.3 当前实现可确认的 genesis 语义

- genesis 当前一定会生成 locked position，并写入 `deadline`。
- genesis 当前不会走 wrap 池，所以不会增加 `syWrapStaking`。
- 测试明确证明：`genesisBySY(...)` 后 `syWrapStaking == 0`，`syTotalStaking` 增加，`uAsset` 最终留在 launcher，不留在用户或 router。
- genesis 入口没有 preview 参数；`genesisByToken(...)` 有 `minSyOut` 和 `minUAssetMinted`，`genesisBySY(...)` 有 `minUAssetMinted`。

### 8.4 launcher 配置校验

- `OutrunRouter` 的 constructor 与 `setMemeverseLauncher(...)` 会在配置期 fail fast，拒绝 `address(0)` 和 `code.length == 0` 的 launcher 地址。
- genesis 流程可把 `memeverseLauncher` 已通过配置期 code-size 校验视为前置条件。
- 这属于运行/测试可观测性加固，不改变 launcher 内部仍是外部信任边界这一语义。

## 9. preview 语义与 slippage 边界

当前 router 暴露的 preview 入口有：

- `previewStakeFromToken(SP, tokenIn, tokenAmount, stakeParam)`
- `previewStakeFromSY(...)`
- `previewWrapStakeFromToken(SP, tokenIn, tokenAmount)`
- `previewWrapRedeem(...)`

当前实现里，这些 preview 的语义边界很明确：

- `previewStakeFromToken(SP, tokenIn, tokenAmount, stakeParam)` 不接收调用者传入的 `SY`；它先从 `SP.SY()` 派生 canonical `SY`，再做两步静态组合：
  - 从 `SP.SY()` 读取 canonical `SY`
  - `SY.previewDeposit(tokenIn, tokenAmount)`
  - `SP.previewStake(amountInSY)`
- `previewStakeFromSY(...)` 只调用 `SP.previewStake(amountInSY)`。
- `previewWrapStakeFromToken(SP, tokenIn, tokenAmount)` 不接收调用者传入的 `SY`；它先从 `SP.SY()` 派生 canonical `SY`，再做两步静态组合：
  - 从 `SP.SY()` 读取 canonical `SY`
  - `SY.previewDeposit(tokenIn, tokenAmount)`
  - `SP.previewWrapStake(amountInSY)`
- `previewWrapRedeem(...)` 只是转发到 `SP.previewWrapRedeem(amountInUAsset, tokenOut)`。

当前 preview 不是完整成交保护，主要有这些边界：

- `previewStakeFromToken(...)` 和 `previewStakeFromSY(...)` 接收 `stakeParam` 参数，但只使用 `stakeParam.lockupDays` 来消除未使用变量告警；preview 结果不反映：
  - `minSyOut`
  - `minUAssetMinted`
  - `owner`
  - `receiver`
  - 不同 `lockupDays` 的差异对 exchangeRate 的影响（如果有的话）
- preview 只 quote，不锁定执行结果；执行时实际成交保护由入口参数负责：
  - `stakeFromToken(...)`、`wrapStakeFromToken(...)`、`genesisByToken(...)` 的 token -> SY 阶段使用 `minSyOut`。
  - locked stake、wrap stake 与 genesis 的 SY -> uAsset 阶段使用 `minUAssetMinted`。
  - `redeemSyToToken(...)` 和 `wrapRedeem(...)` 的赎回阶段使用 `minTokenOut`。

## 10. 当前实现提醒

- locked stake 与 wrap stake 是两套不同表面：
  - locked stake 生成 `positionId`，受 `deadline` 约束。
  - wrap stake 不生成 position，走共享池账务，可随时 `wrapRedeem`。
- router 的 locked stake 路径现在通过 `StakeParam` 支持分离 position owner 和 uAsset receiver：
  - `stakeParam.owner` 是 position owner
  - `stakeParam.receiver` 是 uAsset 接收地址，当 `receiver == address(0)` 时回退到 `owner`
- genesis 当前不是”wrap 后再 launch”，而是”先建 locked position，再把 stake 产出的 `uAsset` 交给 launcher”。
- wrap 池按 principal debt 记账，不会因为汇率上涨自动给用户补发更多 `uAsset`；批准的 harvest rounding fix 要求 `harvestWrapYield(...)` 只能收走高于 `assetToSyUp(wrapUAssetDebt)` 的那部分 `SY`，因此保留当前 exchangeRate 下覆盖 wrap debt 所需的最小 `SY`，多出来的价值体现在剩余超额部分。
- 任何 token / native 与 tokenOut 是否可用，最终都取决于具体 `SY` 实现的 `isValidTokenIn` / `isValidTokenOut`。
