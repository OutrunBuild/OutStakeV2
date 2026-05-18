# OutStakeV2 Accounting

## 1. 文档目的

本文档说明 `OutStakeV2` 当前实现中的核心账务规则，并明确 mixed-decimals 双段换算的本次修复目标/修复后语义，包括 `uAsset` minter-cap、position debt、wrap 池、汇率换算、赎回按比例销债、keeper redeem 分账与 wrap yield harvest。

## 1.1 Upgradeable accounting readiness

当前 implementation 使用 proxy-backed uAsset、SY adapter 与 staking position，并保持本文账务语义：

- `OutrunUniversalAssetsUpgradeable` 的 `mintingStatusTable` 继续按 minter 维度记录 `mintingCap` 与 `amountInMinted`。
- `OutrunStakingPositionUpgradeable` 继续按 position 记录 `syStaked` 与 `UAssetMinted`，并按公共 wrap 池记录 `syTotalStaking`、`syWrapStaking`、`wrapUAssetDebt`。
- `SY` 依赖在 initializer 中写入后保持固定，不新增 `setSY()`，避免 position / wrap debt 对应的 share token 与 exchangeRate source 被替换。
- oracle-backed SY upgradeable variants 可通过 owner-only `setExchangeRateOracle(address)` 更换 `exchangeRateOracle`，但 setter 不改变 balances、shares、position accounting 或 yield-bearing token 配置。
- `OutrunExchangeOracleAdapter` 仍是非 upgradeable thin adapter；本次变更不新增 oracle freshness、bounds、fallback 或多源聚合保证。
- 旧 non-upgradeable contracts 已退出当前产品真源；当前 upgradeable variants 的 V1 storage layout 是后续升级的 canonical layout。

## 2. `uAsset` 的 minter-cap 账务

`OutrunUniversalAssetsUpgradeable` 当前按 minter 维护一张 `mintingStatusTable`：

- `mintingCap`
- `amountInMinted`

当前账务规则是：

- `checkMintableAmount(minter)` 返回 `mintingCap - amountInMinted`，最低到 0。
- `mint(receiver, amount)` 由调用者自己的 minter 额度承担，成功后增加调用者的 `amountInMinted`。
- `repay(account, amount)` 减少调用者（`msg.sender`，即 minter）自己的 `amountInMinted`；`account` 是被 burn 的地址，必须持有足够的 `uAsset`。若 `account != msg.sender`，则还必须先授权 `msg.sender` 消耗对应 `uAsset`。
- `revokeMinter(minter)` 只把 cap 设为 0 以禁止后续 mint，不会自动清空历史已铸债务；既有 `amountInMinted` 保留到后续 repay。
- `transferMinterDebt(from, to, amount)` 当前已实现为 owner-only 操作：要求 `from`、`to` 均非零、彼此不同、`amount` 非零；仅在两个 minter 地址之间迁移未偿债务，不 mint、不 burn、不 transfer，也不改变 `totalSupply` 或任一账户 `balance`。
- `transferMinterDebt` 执行时减少 `from.amountInMinted`、增加 `to.amountInMinted`，并要求来源 minter 具备足额未偿债务、目标 minter 具备足够 `mintingCap` headroom；用途限定为运维修复或迁移，不用于用户债务豁免。
- `transferMinterDebt` 只迁移 `uAsset` 的 minter 级债务；若该 minter 还被 `OutrunStakingPositionUpgradeable` 的 position debt、wrap debt 或其他模块账本引用，操作方必须同步完成对应账本迁移，`uAsset` 不会单独更新这些 position/wrap 记录。

因此，`uAsset` 当前不是”全局总债务池”，而是”按 minter 独立记账的铸造额度和未偿债务”；owner 只能迁移这笔 minter 维度债务归属，不能消灭债务或改变总供应，也不能仅靠 `uAsset` 调账就让 position/wrap 账本自动一致。

## 3. Position debt 账务

`OutrunStakingPositionUpgradeable` 中每个 `Position` 当前记录：

- `owner`
- `syStaked`
- `UAssetMinted`
- `startTime`
- `deadline`

锁仓仓位的初始 debt 规则是：

- 用户 stake `amountInSY`
- 本次修复目标/修复后语义：先计算 `canonicalAssetValue = SY -> canonical asset`，再计算 `principalValue = canonical asset -> uAsset`
- `principalValue` 同时成为初始 `UAssetMinted`
- position 内写入该值，并调用 `uAsset.mint(...)`

这里的关键点是：position debt 不是按固定 1:1 写入，而是按当前 `exchangeRate()` 折算后的 canonical asset value，再归一化成 `uAsset` 记账单位后写入。

## 4. Wrap 池账务

wrap 池当前使用三组聚合账务变量：

- `syTotalStaking`
- `syWrapStaking`
- `wrapUAssetDebt`

`wrapStake` 时：

- 增加 `syTotalStaking`
- 增加 `syWrapStaking`
- 本次修复目标/修复后语义：先计算 `canonicalAssetValue = SY -> canonical asset`，再计算 `principalValue = canonical asset -> uAsset`
- 用 principal value 增加 `wrapUAssetDebt`
- 铸造等额 `uAsset`

`wrapRedeem` 时：

- 先检查 `uAssetDebtUnits = amountInUAsset` 且 `uAssetDebtUnits <= wrapUAssetDebt`
- 本次修复目标/修复后语义：先计算 `canonicalAssetValue = uAsset -> canonical asset`，再计算 `amountInSY = canonical asset -> SY`
- 减少 `syTotalStaking`
- 减少 `syWrapStaking`
- 减少 `wrapUAssetDebt` 中对应的 `uAssetDebtUnits`

当前测试已经说明 wrap 池按 principal accounting 运行，不会因为汇率上涨而自动增加用户的 `uAsset` debt。

## 5. 汇率换算

当前仓库把 `exchangeRate()` 视为 `asset per SY` 的统一换算基准，接口层也明确要求：

- `exchangeRate * syBalance / 1e18` 对应资产值
- 如果用户贡献的是价值 X 的资产，则铸出的 SY 或 debt 应通过同一换算关系推导
- position / wrap debt 的统一语义是：先 `SY -> canonical asset`，再 `canonical asset -> uAsset`；需要从 debt 反推 `SY` 时，则先 `uAsset -> canonical asset`，再 `canonical asset -> SY`
- `canonical asset` 在这里是 `exchangeRate()` 定义的价值单位；`canonicalAssetDecimals` 取自 `SY.assetInfo().assetDecimals`，`uAssetDecimals` 取自 `uAsset.decimals()`
- 以下 mixed-decimals 双段换算是本次修复目标/修复后语义，不把它表述为当前代码已完成行为；具体单位模型与四个基础公式以 [docs/spec/common-foundations.md](/home/azkrale/Web3Project/OutStakeV2/docs/spec/common-foundations.md) 为准

`OutrunStakingPositionUpgradeable` 的相关账务应按四个基础方向换算：

- `SY -> canonical asset`：`canonicalAssetValue = syToAsset(exchangeRate, syAmount)`，必要时使用向上版本
- `canonical asset -> uAsset`：把 `canonicalAssetValue` 归一化为 `uAssetDebtUnits`
- `uAsset -> canonical asset`：把 `uAssetDebtUnits` 反归一化为 `canonicalAssetValue`
- `canonical asset -> SY`：`syAmount = assetToSy(exchangeRate, canonicalAssetValue)`，必要时使用向上版本

rounding matrix：

- mint / stake / wrap stake / `previewStake(amountInSY)` / `previewWrapStake(amountInSY)`：
  - `SY -> canonical asset` 用 down
  - `canonical asset -> uAsset` 用 down
- draw：
  - `SY -> canonical asset` 用 down
  - `canonical asset -> uAsset` 用 down
- wrap redeem：
  - `uAsset -> canonical asset` 用 down
  - `canonical asset -> SY` 用 down
- keeper redeem：
  - `uAsset -> canonical asset` 用 down
  - `canonical asset -> SY` 用 down
- `previewRedeem(positionId, syRedeemed, tokenOut)`：
  - full redeem 直接返回全部剩余 `position.UAssetMinted`
  - partial redeem 对 `position.UAssetMinted * syRedeemed / syStaked` 用 up
  - 若 partial 结果会耗尽剩余 debt，则 preview 必须拒绝该报价
- `previewWrapRedeem(amountInUAsset, tokenOut)`：
  - `uAsset -> canonical asset` 用 down
  - `canonical asset -> SY` 用 down
- harvest coverage：
  - `uAsset -> canonical asset` 用 up
  - `canonical asset -> SY` 用 up

因此，position/wrap 账务都以 `SY` 数量和资产值之间的双向换算为前提，但 mixed-decimals 双段归一化按上表作为本次修复目标落文。

## 6. Draw 账务

`drawUAsset(positionId, recipient)` 当前的账务规则是：

- 本次修复目标/修复后语义：先计算 `canonicalAssetValue = SY -> canonical asset`，再计算 `currentValueInUAsset = canonical asset -> uAsset`
- 再读取已有 `position.UAssetMinted`
- 若 `currentValueInUAsset <= minted`，则可追加铸造额为 0
- 否则只允许铸造差额 `currentValueInUAsset - minted`

成功后：

- `position.UAssetMinted += amountInUAsset`
- 再次检查当前 `uAsset` mint cap 是否足够
- 最后铸造追加的 `uAsset`

因此，draw 当前只把“升值部分”转成新的 debt，不会重写原本金 principal。

## 7. `redeem` 的按比例销债

锁仓仓位赎回时，debt 销毁规则按 full redeem / partial redeem 分叉：

- 用户传入要赎回的 `syRedeemed`
- 若 `syRedeemed == syStaked`，则视为 full redeem，必须精确烧掉该 position 剩余的全部 `position.UAssetMinted`
- 若 `syRedeemed < syStaked`，则视为 partial redeem，`UAssetBurned` 按 `ceil(position.UAssetMinted * syRedeemed / syStaked)` 计算
- partial redeem 额外有一条边界：若上述 ceiling 结果会等于或超过当前剩余 debt，则该 partial 路径必须回退，用户只能改走 full redeem
- `previewRedeem(...)` 与执行期 `redeem(...)` 使用同一条 full / partial 判定与拒绝规则；preview 不能返回一个执行期会因“partial consume all debt”而失败的报价
- position 层先确定 `UAssetBurned` 和允许性，再进入 `uAsset.repay(...)`；正确性不依赖下游出现 `uAsset.repay(0)` 这种零额 repay

如果赎回后 `remainingSY == 0`，position 会被删除；否则保留剩余 principal 与剩余 debt。

这意味着 position redeem 仍然是“按当前仓位内部 debt 比例切片销债”，但 partial 路径使用 ceiling rounding，并显式禁止“剩余 SY 仍在、debt 已被全部烧空”的状态。

这里被销毁的 `position.UAssetMinted` 始终是前述 `SY -> canonical asset -> uAsset` 归一化后记下来的 debt 单位；执行路径不要求在每次 partial redeem 时重新按汇率定价，但该 debt 单位的语义基准保持不变。

## 8. Keeper redeem 分账

`keepRedeem(positionId, amountInUAsset, receiver)` 的账务路径与普通 redeem 不同，当前规则是：

- keeper 提供并烧掉自己持有的 `uAssetDebtUnits = amountInUAsset`
- 本次修复目标/修复后语义：先计算 `canonicalAssetValue = uAsset -> canonical asset`，再计算 `keeperPrincipalSY = canonical asset -> SY`
- 再按显式 down rounding 公式 `syRedeemed = roundDownDiv(syStaked * uAssetDebtUnits, positionUAssetMinted)` 算出本次实际抽出的仓位 `SY`
- 若 `keeperPrincipalSY > syRedeemed`，则必须 clamp 为 `keeperPrincipalSY = syRedeemed`
- 剩余 `ownerExcessSY = syRedeemed - keeperPrincipalSY`

成功后：

- keeper 接收 `keeperPrincipalSY`
- position owner 接收 `ownerExcessSY`
- `revenuePool` 不参与这一路径的分成

测试也直接证明了当前 keeper redeem 没有额外 protocol fee，并且分账输入基于 keeper 烧掉的 `uAsset`，不是 keeper 自己指定的 `SY` 数量。

## 9. Harvest 账务

`harvestWrapYield(tokenOut, minTokenOut)` 的批准修复语义是：只处理 wrap 池中高于当前 exchangeRate 下 wrap debt 最低覆盖需求的那部分 `SY`：

- 先读取 `wrapPoolSY = syWrapStaking`
- 本次修复目标/修复后语义：先按 up 版本计算 `wrapDebtInCanonicalAsset = uAsset -> canonical asset`，再按 up 版本计算 `wrapDebtInSY = canonical asset -> SY`
- 若 `wrapPoolSY <= wrapDebtInSY`，则没有可 harvest 的额外收益
- 否则 `amountInSY = wrapPoolSY - wrapDebtInSY`

成功 harvest 后：

- `syTotalStaking -= amountInSY`
- `syWrapStaking -= amountInSY`
- `wrapUAssetDebt` 不变化
- harvest 后剩余的 `syWrapStaking` 仍满足 `syWrapStaking >= wrapDebtInSY`
- 收益转到 `revenuePool`

因此，harvest 当前抽走的是 wrap 池里“高于 debt 等价 SY 的超额部分”，而不是改变用户未偿 `uAsset` debt。

## 10. 账务边界总结

当前实现可以概括为四条账务边界：

- `uAsset` debt 按 minter 独立记账
- locked position debt 按 position 独立记账
- wrap debt 按公共池聚合记账
- `exchangeRate()` 与 `SYUtils` 是 `SY` 数量和资产值之间的统一换算基准

凡是外部协议如何生成该 `exchangeRate()` 的问题，都只属于本地依赖边界；当前本仓库能直接证明的是“上层账务如何消费这个汇率”，而不是外部汇率来源本身的真实性。
