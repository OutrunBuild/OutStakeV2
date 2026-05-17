# OutStakeV2 Accounting

## 1. 文档目的

本文档说明 `OutStakeV2` 当前实现中的核心账务规则，包括 `uAsset` minter-cap、position debt、wrap 池、汇率换算、赎回按比例销债、keeper redeem 分账与 wrap yield harvest。

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
- 合约用 `SY.exchangeRate()` 通过 `SYUtils.syToAsset(...)` 算出 `principalValue`
- `principalValue` 同时成为初始 `UAssetMinted`
- position 内写入该值，并调用 `uAsset.mint(...)`

这里的关键点是：position debt 不是按固定 1:1 写入，而是按当前 `exchangeRate()` 折算后的资产值写入。

## 4. Wrap 池账务

wrap 池当前使用三组聚合账务变量：

- `syTotalStaking`
- `syWrapStaking`
- `wrapUAssetDebt`

`wrapStake` 时：

- 增加 `syTotalStaking`
- 增加 `syWrapStaking`
- 按当前 `exchangeRate()` 折算出 principal value
- 用 principal value 增加 `wrapUAssetDebt`
- 铸造等额 `uAsset`

`wrapRedeem` 时：

- 先检查 `amountInUAsset <= wrapUAssetDebt`
- 再把 `amountInUAsset` 用 `assetToSy` 换算成 `amountInSY`
- 减少 `syTotalStaking`
- 减少 `syWrapStaking`
- 减少 `wrapUAssetDebt`

当前测试已经说明 wrap 池按 principal accounting 运行，不会因为汇率上涨而自动增加用户的 `uAsset` debt。

## 5. 汇率换算

当前仓库把 `exchangeRate()` 视为 `asset per SY` 的统一换算基准，接口层也明确要求：

- `exchangeRate * syBalance / 1e18` 对应资产值
- 如果用户贡献的是价值 X 的资产，则铸出的 SY 或 debt 应通过同一换算关系推导

`OutrunStakingPositionUpgradeable` 当前账务描述涉及两种方向的换算：

- `syToAsset(exchangeRate, syAmount)`：把 `SY` principal 换成资产值，用于 stake、wrap stake、draw 预览
- `assetToSy(exchangeRate, assetAmount)`：把 `uAsset` debt 换成 `SY`，用于 wrap redeem、keeper redeem
- `assetToSyUp(exchangeRate, assetAmount)`：把 `uAsset` debt 向上取整换成 `SY`，用于 `harvestWrapYield` 的最小 retained debt coverage

因此，当前仓库的 position/wrap 账务，都以 `SY` 数量和资产值之间的双向换算为前提。

## 6. Draw 账务

`drawUAsset(positionId, recipient)` 当前的账务规则是：

- 先用当前 `exchangeRate()` 计算 position 的 `currentValue`
- 再读取已有 `position.UAssetMinted`
- 若 `currentValue <= minted`，则可追加铸造额为 0
- 否则只允许铸造差额 `currentValue - minted`

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

## 8. Keeper redeem 分账

`keepRedeem(positionId, amountInUAsset, receiver)` 的账务路径与普通 redeem 不同，当前规则是：

- keeper 提供并烧掉自己持有的 `amountInUAsset`
- 先按 `keeperPrincipalSY = assetToSy(amountInUAsset)` 算出 keeper 理论本金
- 再按 `syRedeemed = syStaked * amountInUAsset / positionUAssetMinted` 算出本次实际抽出的仓位 `SY`
- 若理论本金大于实际可抽出的 `syRedeemed`，则 keeper 只能拿到 `syRedeemed`
- 剩余 `ownerExcessSY = syRedeemed - keeperPrincipalSY`

成功后：

- keeper 接收 `keeperPrincipalSY`
- position owner 接收 `ownerExcessSY`
- `revenuePool` 不参与这一路径的分成

测试也直接证明了当前 keeper redeem 没有额外 protocol fee，并且分账输入基于 keeper 烧掉的 `uAsset`，不是 keeper 自己指定的 `SY` 数量。

## 9. Harvest 账务

`harvestWrapYield(tokenOut, minTokenOut)` 的批准修复语义是：只处理 wrap 池中高于当前 exchangeRate 下 wrap debt 最低覆盖需求的那部分 `SY`：

- 先读取 `wrapPoolSY = syWrapStaking`
- 再计算 `wrapDebtInSY = assetToSyUp(wrapUAssetDebt)`
- 若 `wrapPoolSY <= wrapDebtInSY`，则没有可 harvest 的额外收益
- 否则 `amountInSY = wrapPoolSY - wrapDebtInSY`

成功 harvest 后：

- `syTotalStaking -= amountInSY`
- `syWrapStaking -= amountInSY`
- `wrapUAssetDebt` 不变化
- harvest 后剩余的 `syWrapStaking` 仍满足 `syWrapStaking >= assetToSyUp(wrapUAssetDebt)`，等价于 `syToAsset(exchangeRate, syWrapStaking) >= wrapUAssetDebt`
- 收益转到 `revenuePool`

因此，harvest 当前抽走的是 wrap 池里“高于 debt 等价 SY 的超额部分”，而不是改变用户未偿 `uAsset` debt。

## 10. 账务边界总结

当前实现可以概括为四条账务边界：

- `uAsset` debt 按 minter 独立记账
- locked position debt 按 position 独立记账
- wrap debt 按公共池聚合记账
- `exchangeRate()` 与 `SYUtils` 是 `SY` 数量和资产值之间的统一换算基准

凡是外部协议如何生成该 `exchangeRate()` 的问题，都只属于本地依赖边界；当前本仓库能直接证明的是“上层账务如何消费这个汇率”，而不是外部汇率来源本身的真实性。
