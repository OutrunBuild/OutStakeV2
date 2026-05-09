# Access Control

## 目标

本文只基于当前 upgradeable 真源整理权限边界：

- `src/assets/base/OutrunUniversalAssetsUpgradeable.sol`
- `src/position/OutrunStakingPositionUpgradeable.sol`
- `src/router/OutrunRouter.sol`
- `src/yield/SYBaseUpgradeable.sol`
- `src/libraries/oracle/OutrunExchangeOracleAdapter.sol`

## 权限模型

- protocol owner 是 multisig
- 不引入 timelock
- 不引入额外 governance module
- router 仍只有 `setMemeverseLauncher(address)` owner 入口
- oracle adapter 不拥有 proxy upgrade 权限

UUPS 边界：

- `OutrunUniversalAssetsUpgradeable` 由 owner 授权升级
- `OutrunStakingPositionUpgradeable` 由 owner 授权升级
- `SYBaseUpgradeable` 为所有 SY adapters 提供 UUPS authority
- oracle-backed SY upgradeable variants 只有 owner-only `setExchangeRateOracle(address)`

## 重要结果

- `uAsset` 的 mint cap 仍由 owner 配置
- position 的 `setMinStake`、`setUAsset`、`setRevenuePool`、`setKeeper` 仍是 owner 权限
- router、SY、position 的公开入口都仍受 allowance、余额、pause 与下游校验约束

