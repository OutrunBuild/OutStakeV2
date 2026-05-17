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
- Lista: `OutrunSlisBNBSYUpgradeable`
- Aster: `OutrunAsBNBSYUpgradeable`
- Generic oracle-backed L2 staked token: `OutrunL2StakedTokenSYUpgradeable`

## Evidence Rules

- Local unit tests prove only local adapter branching, arithmetic, token validation, pause, owner setter, and revert behavior.
- Fork tests prove only pinned-block interaction with configured upstream contracts.
- External protocol semantics require primary evidence: verified source, official upstream repository, official documentation, or reproducible fork trace.
- If no primary evidence exists for a behavior, it remains a trust boundary and must not be described as a local guarantee.

## 外部依赖边界

- `OutrunL2WrappableWstETHSYUpgradeable` 的 OP path rate source是 upstream L2 stETH token-native conversion call；adapter 依赖外部 token 合约的 `getTokensByShares` 行为，不在本地 oracle adapter 内提供 freshness、bounds、fallback 或多源聚合保证
- `OutrunL2StakedUsdsSYUpgradeable` 的 `exchangeRate()` 来源是 PSM3 `previewSwapExactIn(yieldBearingToken -> USDS)`，不是 oracle；quote、liquidity、token config 和 governance config 都属于外部依赖
- oracle-backed variants 只消费配置好的单一 oracle 输出；当前实现不提供 freshness、bounds、fallback 或多源聚合
- pinned fork evidence 必须固定 block；不得把 latest fork 结果写成本地保证或长期语义保证
