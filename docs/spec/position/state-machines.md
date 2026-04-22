# OutStakeV2 State Machines

## 1. 文档目的

本文档把 `OutStakeV2` 当前用户可见主流程整理成状态机表达，帮助读者理解各个入口如何改变 position、wrap 池、`uAsset` debt 与 pause 状态。本文只描述当前本地代码里已经存在的流程。

## 2. 直接 stake 生命周期

直接 stake 对应 `OutrunStakingPosition.stake(...)`，以及 router 的 `stakeFromToken` / `stakeFromSY` 在进入 position 后的同一路径。

当前生命周期如下：

1. 调用前状态：用户持有 `SY`，或先经 router 把 token 转成 `SY`。
2. 入口校验：`positionOwner` 与 `uAssetReceiver` 不能为零地址，`amountInSY` 需满足 `minStake`，合约不能处于 paused。
3. 资产进入：`SY` 被转入 `OutrunStakingPosition`。
4. principal 定价：用当前 `exchangeRate()` 把 `amountInSY` 折算成 `principalValue`。
5. debt 上限校验：检查当前 `uAsset` 给该 position 合约地址留下的 mintable cap 是否足够。
6. 状态写入：增加 `syTotalStaking`，生成新的 `positionId`，写入 position。
7. 债务铸造：调用 `uAsset.mint(uAssetReceiver, UAssetMinted)`。
8. 完成状态：position 进入“已创建、未到期、可 draw、不可 redeem”的活跃状态。

## 3. Draw 生命周期

`drawUAsset(positionId, recipient)` 只作用于已存在 position，当前状态机如下：

1. 前置状态：position 存在，调用者必须是 position owner，合约不能 paused。
2. 估值阶段：按当前 `exchangeRate()` 计算仓位价值。
3. 可追加额度计算：若当前价值不高于已铸 debt，则流程回退；否则差额即 `amountInUAsset`。
4. 状态更新：增加 `position.UAssetMinted`。
5. cap 校验与铸造：检查 `uAsset` mint cap，随后铸造新的 `uAsset` 到 `recipient`。
6. 完成状态：position 仍是活跃仓位，但未偿 debt 增大。

因此，draw 不会改变 lock deadline，也不会改变 `syStaked`。

## 4. 普通 redeem 生命周期

`redeem(positionId, syRedeemed, receiver, tokenOut)` 当前只允许已到期的 position owner 发起。

生命周期如下：

1. 前置状态：position 存在；调用者是 owner；`block.timestamp >= deadline`；合约未 paused。
2. 输入校验：`syRedeemed` 不能为 0，且不能超过当前 `position.syStaked`。
3. debt 计算：按仓位内部比例算出 `UAssetBurned`。
4. debt 清偿：对调用者执行 `uAsset.repay(msg.sender, UAssetBurned)`。
5. position 更新：
   - `syTotalStaking` 减少 `syRedeemed`
   - `position.syStaked` 减少 `syRedeemed`
   - `position.UAssetMinted` 减少 `UAssetBurned`
   - 若剩余 `SY` 为 0，则删除 position
6. 资产输出：
   - `tokenOut == SY` 时直接转出 `SY`
   - 否则调用 `SY.redeem(...)` 产出目标 token
7. 完成状态：position 进入“部分赎回后继续存在”或“已清空删除”。

## 5. Wrap stake / wrap redeem 生命周期

### 5.1 Wrap stake

`wrapStake(amountInSY, uAssetRecipient)` 当前状态机如下：

1. 前置状态：合约未 paused；输入数量和 recipient 有效。
2. 资产进入：`SY` 转入 position 合约。
3. principal 定价：把 `amountInSY` 按当前 `exchangeRate()` 折算成 principal value。
4. cap 校验：检查当前 `uAsset` mint cap。
5. 聚合账务更新：
   - `syTotalStaking += amountInSY`
   - `syWrapStaking += amountInSY`
   - `wrapUAssetDebt += principalValue`
6. 铸造：向 `uAssetRecipient` 铸造 `principalValue` 对应的 `uAsset`。

### 5.2 Wrap redeem

`wrapRedeem(amountInUAsset, receiver, tokenOut)` 当前状态机如下：

1. 前置状态：合约未 paused；输入合法；`amountInUAsset <= wrapUAssetDebt`。
2. 份额换算：把 `amountInUAsset` 换算成 `amountInSY`。
3. wrap 池余额校验：若 `amountInSY > syWrapStaking` 则回退。
4. debt 清偿：对调用者执行 `uAsset.repay(msg.sender, amountInUAsset)`。
5. 聚合账务更新：
   - `syTotalStaking -= amountInSY`
   - `syWrapStaking -= amountInSY`
   - `wrapUAssetDebt -= amountInUAsset`
6. 资产输出：
   - `tokenOut == SY` 时直接输出 `SY`
   - 否则通过 `SY.redeem(...)` 输出目标 token

当前 wrap 流程始终作用于共享池，不会生成或消费独立 `positionId`。

## 6. Keeper redeem 生命周期

`keepRedeem(positionId, amountInUAsset, receiver)` 当前对应一个特权状态机：

1. 前置状态：调用者必须是 `keeper`；position 存在；position 已到期；合约未 paused。
2. 输入校验：`amountInUAsset` 不能为 0，且不能高于 `position.UAssetMinted`。
3. debt 清偿：keeper 先烧掉自己提供的 `uAsset`。
4. `SY` 分解：
   - 计算 keeper 对应本金 `keeperPrincipalSY`
   - 计算本次从仓位释放的 `syRedeemed`
   - 计算 owner 可拿回的 `ownerExcessSY`
5. position 更新：与普通 redeem 一样减少 `syTotalStaking`、position principal 和 position debt。
6. 分账输出：
   - `receiver` 接 keeper principal
   - position owner 接剩余 excess `SY`

因此，keeper redeem 当前是“keeper 帮 position 结清一部分 debt，并取回相应本金”的状态机，而不是 owner 赎回的别名。

## 7. Harvest wrap yield 生命周期

`harvestWrapYield(tokenOut)` 用于提取 wrap 池中超出债务等价 SY 的超额收益，当前状态机如下：

1. 前置状态：
   - 调用者必须是 position 合约的 `owner`
   - 合约未 paused
   - wrap 池有盈余：`syWrapStaking > assetToSy(wrapUAssetDebt)`

2. 盈余计算：
   - 读取 `wrapPoolSY = syWrapStaking`
   - 计算 `wrapDebtInSY = assetToSy(wrapUAssetDebt)`（用当前 exchangeRate 换算）
   - 若 `wrapPoolSY <= wrapDebtInSY`，则没有可 harvest 的收益，回退
   - 否则 `harvestAmount = wrapPoolSY - wrapDebtInSY`

3. 状态变化：
   - `syTotalStaking -= harvestAmount`
   - `syWrapStaking -= harvestAmount`
   - `wrapUAssetDebt` 不变（用户债务不受影响）

4. 收益输出：
   - 若 `tokenOut == SY`，直接将 `harvestAmount` 的 SY 转给 `revenuePool`
   - 否则调用 `SY.redeem(revenuePool, harvestAmount, tokenOut, 0, false)` 将收益兑换为 tokenOut

5. 后置条件：
   - wrap 池仍有足够的 SY 覆盖 `wrapUAssetDebt`（即 `syWrapStaking >= assetToSy(wrapUAssetDebt)`）
   - `revenuePool` 收到超额收益
   - 用户 `uAsset` 债务不变

## 8. Pause / unpause 的影响

当前仓库存在两类 pause 语义：

### 8.1 Position 级 pause

`OutrunStakingPosition.pause()` / `unpause()` 由 owner 控制，并直接影响带 `whenNotPaused` 的业务入口：

- `stake`
- `drawUAsset`
- `wrapStake`
- `redeem`
- `wrapRedeem`
- `keepRedeem`
- `harvestWrapYield`

对应的 preview / view 函数不受该 pause 影响。

### 8.2 SY token 级 pause

`SYBase` 继承 `OutrunERC20Pausable`，因此 `SY` token 的转账、mint、burn 本身也受 owner pause 控制。当前这会影响：

- `SY.deposit` 中的 `_mint`
- `SY.redeem` 中的 `_burn`
- 常规 `SY` transfer 行为

因此，在当前实现里，用户流程既可能被 position 级 pause 阻断，也可能被底层 `SY` token pause 阻断。
