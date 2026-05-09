# OutStakeV2 Testing And Evidence

## 测试布局

当前产品证据主要分布在：

- `test/assets/`
- `test/position/`
- `test/router/`
- `test/upgradeable/`
- `test/support/`

`test/upgradeable/` 是收益层当前证据入口，覆盖 `SYBaseUpgradeable`、proxy-backed adapters、oracle setter 以及 router/position 的 proxy 集成。

## 直接证据

- `OutrunUniversalAssets` 的 mint cap、repay、OFT shared-decimal envelope 与 rate-limit quote。
- `OutrunStakingPosition` 的建仓、补提债务、到期赎回、keeper 代偿赎回、wrap stake、wrap redeem 与收益 harvest。
- `OutrunRouter` 的 caller-funded pull 模式、native/erc20 输入约束、wrap 路径与 genesis mock 路径。
- `SYBaseUpgradeable` 的 initializer、pause、redeem 重入边界。
- proxy-backed SY adapters 的核心 deposit / redeem / preview / exchangeRate 行为。
- oracle-backed upgradeable SY variants 的 owner-only `setExchangeRateOracle(address)` 边界。

## 仍需留意

- 外部协议真实结算、价格更新、队列、权限和可用性仍属于外部依赖。
- 当前测试更偏向统一 proxy-backed 回归，而非每个 adapter 的独立专项集。

