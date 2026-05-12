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
