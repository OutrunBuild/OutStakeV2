# OutStakeV2 Yield Adapters

## 文档目的

本文档汇总当前 upgradeable SY adapter 的统一行为和产品边界。

## 统一规则

- 所有 SY adapters 都通过 `SYBaseUpgradeable` 提供的 proxy-backed 抽象实现
- 所有 adapter 都保留 `deposit`、`redeem`、`previewDeposit`、`previewRedeem`、`exchangeRate`、`getTokensIn`、`getTokensOut`
- oracle-backed variants 通过 `exchangeRateOracle` storage 获取汇率
- Optimism-specific `OutrunL2WrappableWstETHSYUpgradeable` 不使用 `exchangeRateOracle` storage / getter / setter；`exchangeRate()` 直接返回 `IL2StETH.getTokensByShares(1 ether)`
- adapter 本身不重复继承 UUPS

## 代表性 adapter

- `OutrunAaveV3SYUpgradeable`
- `OutrunWeETHSYUpgradeable`
- `OutrunWstETHSYUpgradeable`
- `OutrunL2WstETHSYUpgradeable`
- `OutrunL2WrappableWstETHSYUpgradeable`
- `OutrunStakedUsdsSYUpgradeable`
- `OutrunL2StakedUsdsSYUpgradeable`
- `OutrunStakedUSDeSYUpgradeable`
- `OutrunSlisBNBSYUpgradeable`
- `OutrunAsBNBSYUpgradeable`
- `OutrunL2StakedTokenSYUpgradeable`

## 当前证据

- `test/upgradeable/SYUpgradeable.t.sol`
- `test/upgradeable/SYAdaptersUpgradeable.t.sol`
- `test/upgradeable/OracleSetterUpgradeable.t.sol`

## 当前缺口

- 不是每个 adapter 都有独立专项测试
- 外部协议行为仍属于外部依赖
- `OutrunL2WrappableWstETHSYUpgradeable` 的 OP 路径仍依赖上游 L2 stETH / wstETH token conversion 行为；本文档只规定 adapter 调用边界，不声明外部 token 转换规则本身
- `OutrunL2WstETHSYUpgradeable` 仍是 oracle-backed 的 only-wstETH 变体
