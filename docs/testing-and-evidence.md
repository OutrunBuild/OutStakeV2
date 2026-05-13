# OutStakeV2 Testing And Evidence

## 测试布局

当前产品证据主要分布在：

- `test/upgradeable/`
- `test/deploy/`
- `test/support/`

`test/upgradeable/` 是当前产品测试主入口，覆盖 upgradeable assets、position、router proxy integration、SY base、proxy-backed adapters、oracle setter、fork-only SY adapter evidence、fuzz、invariant 和 adversarial cases。

`test/deploy/` 覆盖 upgradeable deployment scripts。

`test/support/` 保留 mock、helper、library 和 token helper 证据。

`test/{assets,integration,position,router,security,yield}/` 当前不承载 `.sol` 测试文件；相关证据已迁移到 `test/upgradeable/` 或 `test/deploy/`。

## 直接证据

- `OutrunUniversalAssetsUpgradeable` 的 mint cap、repay、OFT shared-decimal envelope 与 rate-limit quote。
- `OutrunOFTUpgradeable` 的 OFT shared-decimal envelope 与 rate-limit quote。
- `OutrunStakingPositionUpgradeable` 的建仓、补提债务、到期赎回、keeper 代偿赎回、wrap stake、wrap redeem 与收益 harvest。
- `OutrunRouter` 的 caller-funded pull 模式、native/erc20 输入约束、wrap 路径与 genesis mock 路径。
- `SYBaseUpgradeable` 的 initializer、pause、redeem 重入边界。
- proxy-backed SY adapters 的核心 deposit / redeem / preview / exchangeRate 行为。
- oracle-backed upgradeable SY variants 的 owner-only `setExchangeRateOracle(address)` 边界。
- `OutstakeScript` 与 `YieldDeployScript` 的 upgradeable deployment evidence。

## Harness 映射

`.harness/policy.json` 的 `test_mapping` 当前把证据归到：

- assets：`test/upgradeable/OutrunOFTUpgradeable.t.sol`、`test/upgradeable/OutrunUniversalAssetsUpgradeable.t.sol`
- position：`test/upgradeable/OutrunStakingPositionUpgradeable.t.sol`、`test/upgradeable/OutrunStakingPositionFuzzUpgradeable.t.sol`、`test/upgradeable/OutrunStakingPositionInvariantUpgradeable.t.sol`
- router：`test/upgradeable/OutrunRouterUpgradeable.t.sol`、`test/upgradeable/OutrunRouterFuzzUpgradeable.t.sol`、`test/upgradeable/RouterProxyIntegration.t.sol`
- yield：`test/upgradeable/SYUpgradeable.t.sol`、`test/upgradeable/SYAdaptersUpgradeable.t.sol`、`test/upgradeable/SYAdaptersFork.t.sol`、`test/upgradeable/OracleSetterUpgradeable.t.sol`
- deployment：`test/deploy/OutstakeScriptUpgradeable.t.sol`、`test/deploy/YieldDeployScriptUpgradeable.t.sol`
- security：`test/upgradeable/AdversarialTestsUpgradeable.t.sol`

## 仍需留意

- 外部协议真实结算、价格更新、队列、权限和可用性仍属于外部依赖。
- 当前测试更偏向统一 proxy-backed 回归，而非每个 adapter 的独立专项集。
