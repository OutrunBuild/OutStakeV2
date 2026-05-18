# Common Foundations

## 目标

本文档只记录当前产品真源里会持续影响上层语义的基础层规则：

- `src/libraries/TokenHelper.sol`
- `src/libraries/ReentrancyGuard.sol`
- `src/libraries/SYUtils.sol`
- `src/assets/base/OutrunERC20Upgradeable.sol`
- `src/assets/base/OutrunERC20PausableUpgradeable.sol`
- `src/assets/omnichain/OutrunOFTUpgradeable.sol`
- `src/libraries/oracle/OutrunExchangeOracleAdapter.sol`
- `test/upgradeable/SYUpgradeable.t.sol`
- `test/upgradeable/SYAdaptersUpgradeable.t.sol`
- `test/upgradeable/OracleSetterUpgradeable.t.sol`

## 基础规则

- `address(0)` 作为 `NATIVE`
- `nonReentrant` 由 transient guard 提供
- `1e18` 是统一换算基准
- oracle-backed upgradeable adapters 通过 `exchangeRateOracle` storage 读取外部汇率
- `OutrunExchangeOracleAdapter` 只做精度归一化，不做 freshness、bounds、fallback 或多源聚合
- `uAsset` minter 债务由 `amountInMinted` 记录；`revokeMinter(minter)` 通过把 `mintingCap` 置零禁止后续 mint，但保留既有 `amountInMinted` 直到偿还
- `transferMinterDebt(from, to, amount)` 当前已实现为 owner-only 操作：要求 `from`、`to` 均非零、彼此不同、`amount` 非零；仅在两个 minter 地址之间迁移未偿债务，不 mint、不 burn、不 transfer，也不改变 `totalSupply` 或任一账户 `balance`
- `transferMinterDebt` 执行时减少 `from.amountInMinted`、增加 `to.amountInMinted`，并要求来源 minter 具备足额未偿债务、目标 minter 具备足够 `mintingCap` headroom；用途限定为运维修复或迁移，不用于用户债务豁免
- `transferMinterDebt` 只迁移 `uAsset` 的 minter 级债务；若该 minter 还受 position、wrap 等模块账本约束，操作方只能在这些账本保持一致的协调迁移流程中使用它，`uAsset` 本身不会同步更新 position/wrap 台账

## 单位模型（本次修复目标）

本节定义 mixed-decimals 双段换算的本次修复目标/修复后语义，不把它表述为当前代码已完成行为。

- `exchangeRate` 的单位是 `canonical asset per 1 SY`，并按 `1e18` 缩放
- `canonicalAssetDecimals = SY.assetInfo().assetDecimals`
- `uAssetDecimals = uAsset.decimals()`
- `syAmount` 表示 `SY` 数量
- `canonicalAssetValue` 表示 canonical asset 单位下的价值
- `uAssetDebtUnits` 表示 `uAsset` decimals 口径下的债务单位

记：

- `roundDownDiv(x, y) = floor(x / y)`
- `roundUpDiv(x, y) = ceil(x / y) = floor((x + y - 1) / y)`

四个基础换算公式：

- `SY -> canonical asset`
  - down: `canonicalAssetValue = roundDownDiv(syAmount * exchangeRate, 1e18)`
  - up: `canonicalAssetValue = roundUpDiv(syAmount * exchangeRate, 1e18)`
- `canonical asset -> uAsset`
  - 若 `uAssetDecimals >= canonicalAssetDecimals`，`uAssetDebtUnits = canonicalAssetValue * 10 ** (uAssetDecimals - canonicalAssetDecimals)`
  - 若 `uAssetDecimals < canonicalAssetDecimals`，down: `uAssetDebtUnits = roundDownDiv(canonicalAssetValue, 10 ** (canonicalAssetDecimals - uAssetDecimals))`
  - 若 `uAssetDecimals < canonicalAssetDecimals`，up: `uAssetDebtUnits = roundUpDiv(canonicalAssetValue, 10 ** (canonicalAssetDecimals - uAssetDecimals))`
- `uAsset -> canonical asset`
  - 若 `canonicalAssetDecimals >= uAssetDecimals`，`canonicalAssetValue = uAssetDebtUnits * 10 ** (canonicalAssetDecimals - uAssetDecimals)`
  - 若 `canonicalAssetDecimals < uAssetDecimals`，down: `canonicalAssetValue = roundDownDiv(uAssetDebtUnits, 10 ** (uAssetDecimals - canonicalAssetDecimals))`
  - 若 `canonicalAssetDecimals < uAssetDecimals`，up: `canonicalAssetValue = roundUpDiv(uAssetDebtUnits, 10 ** (uAssetDecimals - canonicalAssetDecimals))`
- `canonical asset -> SY`
  - down: `syAmount = roundDownDiv(canonicalAssetValue * 1e18, exchangeRate)`
  - up: `syAmount = roundUpDiv(canonicalAssetValue * 1e18, exchangeRate)`

## Pause 与跨链 OFT 执行边界

`OutrunERC20PausableUpgradeable` 的 pause 语义用于阻断用户主动发起的本地 ERC20 transfer、mint、burn 业务入口，也阻断 pause 之后用户在源链新发起的 OFT outbound send。

`OutrunOFTUpgradeable` 的 LayerZero inbound `_credit` 执行路径是跨链消息生命周期的一部分，不能因为目标链本地 pause 阻断已经进入跨链流程的代币。因此，`_credit` 直接走基础 ERC20 `_update`，不经过 `OutrunERC20PausableUpgradeable._update whenNotPaused`。

该规则只豁免 inbound `_credit`，不扩大到用户主动发起的 outbound send、普通用户 transfer、`uAsset.mint`、`SY.deposit` 或 `SY.redeem`。

## 结论

当前上层产品语义仍然建立在：

1. 统一的 native/ERC20 资金契约
2. 统一的 allowance 语义
3. 统一的 transient reentrancy guard
4. 统一的 18-decimal 兑换规则
5. proxy-backed upgradeable deployment model
