# Common Foundations

## 目标

本文档只记录当前产品真源里会持续影响上层语义的基础层规则：

- `src/libraries/TokenHelperUpgradeable.sol`
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

## 结论

当前上层产品语义仍然建立在：

1. 统一的 native/ERC20 资金契约
2. 统一的 allowance 语义
3. 统一的 transient reentrancy guard
4. 统一的 18-decimal 兑换规则
5. proxy-backed upgradeable deployment model

