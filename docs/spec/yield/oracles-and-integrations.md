# OutStakeV2 Oracles And Integrations

## 文档目的

本文档只说明当前 upgradeable 产品真源里与 oracle 和外部 integration 相关的边界。

## 边界

- `OutrunExchangeOracleAdapter` 仍是非 upgradeable helper
- oracle-backed SY upgradeable variants 通过 `exchangeRateOracle` storage 指向 oracle adapter
- `setExchangeRateOracle(address)` 是 owner-only
- 不提供 freshness、heartbeat、deviation bounds、fallback 或多源聚合保证
- `OutrunL2WrappableWstETHSYUpgradeable` 是 Optimism-specific wrappable L2 wstETH variant，不属于 oracle-backed variant；当前实现没有 `exchangeRateOracle` storage / getter / setter，`exchangeRate()` 返回 `IL2StETH.getTokensByShares(1 ether)`

## 当前 product integration surface

- Aave: `OutrunAaveV3SYUpgradeable`
- Ether.fi: `OutrunWeETHSYUpgradeable`
- Lido: `OutrunWstETHSYUpgradeable`、oracle-backed only-wstETH `OutrunL2WstETHSYUpgradeable`、Optimism-specific wrappable `OutrunL2WrappableWstETHSYUpgradeable`
- Sky: `OutrunStakedUsdsSYUpgradeable`、`OutrunL2StakedUsdsSYUpgradeable`
- Ethena: `OutrunStakedUSDeSYUpgradeable`

## 外部依赖边界

- `OutrunL2WrappableWstETHSYUpgradeable` 的 OP path rate source是 upstream L2 stETH token-native conversion call；adapter 依赖外部 token 合约的 `getTokensByShares` 行为，不在本地 oracle adapter 内提供 freshness、bounds、fallback 或多源聚合保证
