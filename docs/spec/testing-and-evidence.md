# OutStakeV2 Testing And Evidence

## 1. 文档目的

本文档说明 `OutStakeV2` 当前仓库的测试布局、证据分层，以及 `docs/spec/*.md` 与源码、测试、`docs/superpowers/**` 的关系。本文只记录当前仓库里能直接读取到的事实，不对未覆盖部分做扩展推断。

## 2. 测试目录布局

当前 Foundry 测试目录按业务域拆分：

| 目录 | 当前用途 | 代表文件 |
| --- | --- | --- |
| `test/assets/` | 资产层测试，主要覆盖 `uAsset` 的 mint cap、repay、flash fee 与部分 OFT 安全边界 | `test/assets/OutrunUniversalAssets.t.sol` |
| `test/position/` | 仓位层测试，覆盖 stake、draw、redeem、keep redeem、wrap 池、harvest、权限与大数账务 | `test/position/OutrunStakingPosition.t.sol` |
| `test/router/` | 路由层测试，覆盖 caller-funded pull 模式、native/erc20 输入、wrap redeem、genesis mock 路径与最小铸造约束 | `test/router/OutrunRouter.t.sol` |
| `test/yield/` | 收益层测试，覆盖 `SYBase` 通用约束与若干 adapter 的 deposit / redeem / exchangeRate 行为 | `test/yield/SYBaseDeposit.t.sol`、`test/yield/OutrunAaveV3SY.t.sol`、`test/yield/OutrunWeETHSY.t.sol`、`test/yield/OutrunWstETHSY.t.sol`、`test/yield/OutrunL2WrappableWstETHSY.t.sol` |
| `test/support/` | 测试支撑面，包含 mock token、mock oracle、faucet，以及 oracle warning 测试 | `test/support/MockOracleWarnings.t.sol`、`test/support/MockUSDC.sol`、`test/support/Faucet.sol` |

## 3. 直接测试到的行为

以下行为目前有明确的本地测试证据：

- `OutrunUniversalAssets` 的 minter cap、生效中的剩余额度、`revokeMinter`、`repay(account, amount)` 债务回收、flash fee receiver 行为、`quoteSend` 溢出保护。
- `OutrunStakingPosition` 的 position 创建、owner/receiver 分离、`drawUAsset` 只铸造升值部分、按比例赎回 debt、keeper redeem 分账、wrap 池按 principal 记账、wrap yield harvest、权限控制与大数路径。
- `OutrunRouter` 的 caller-funded pull 模式、native 输入约束、直接 mint/redeem `SY`、wrap stake / wrap redeem、以及 `genesisBySY` 走锁仓仓位而非 wrap 池。
- `SYBase` 的 native 与 ERC20 输入约束、redeem 外层成功且回调重入被阻断的行为。
- `OutrunAaveV3SY`、`OutrunWeETHSY`、`OutrunWstETHSY`、`OutrunL2WrappableWstETHSY` 的部分核心 adapter 行为。
- `OutrunExchangeOracleAdapter` 对零值或负值 oracle answer 的拒绝逻辑。

这些行为可以被视为“文档表述有直接测试支撑”的内容，但仍应以 `src/**` 的实际实现为准。

## 4. 仅代码存在或部分测试的表面

下列表面当前更适合归类为“代码已实现，但测试证据不完整”：

- `OutrunOFT` 的完整跨链消息流、对端配置正确性与远端 mint/burn 配合。当前本地只看到部分安全边界测试，不构成完整跨链行为证明。
- `OutrunSlisBNBSY`。仓库中存在源码与部署接线路径，但未见独立 adapter 测试文件。
- `OutrunStakedUsdsSY`、`OutrunL2StakedUsdsSY`、`OutrunStakedUSDeSY`、`OutrunL2WstETHSY`、`OutrunL2StakedTokenSY`。这些表面在源码中已定义，但当前测试目录未提供同名正式测试文件。
- deployment scripts。`OutstakeScript.s.sol`、`YieldDeployScript.s.sol`、`OutrunDeployer.sol` 能证明部署和接线意图，但它们不是运行时产品行为测试。
- router 的 genesis 集成当前只有 `genesisBySY` 在本地 mock launcher 下有直接测试，且该测试只证明本地资金流接口；`genesisByToken` 仍不应被表述为已有直接覆盖，也不构成外部 `Memeverse` 系统语义证明。

因此，`docs/spec/*.md` 在描述这些表面时应明确使用“本地依赖边界”“当前接线方式”“源码表面存在”这类措辞，而不是把外部协议语义写成已确认事实。

## 5. `docs/spec/*.md` 与 `src/**`、`test/**`、`docs/superpowers/**` 的关系

`docs/spec/*.md` 的职责是把当前实现压缩成正式规格表达，但它不是新的真源层。三者关系如下：

- `src/**` 是实现真源。任何状态变量、权限边界、资金流和外部调用关系，最终都以源码为准。
- `test/**` 是行为证据层。它说明哪些实现被直接验证、哪些只验证了局部安全边界。
- `docs/spec/*.md` 是面向阅读者的正式说明层，只能总结 `src/**` 与 `test/**` 已经成立的内容。
- `docs/superpowers/specs/**` 与 `docs/superpowers/plans/**` 是本地设计与计划工件，不是当前实现规格真源。正式 spec 可以参考其中的话题边界，但不能把其中未落地内容升级为“当前规则”。

换句话说，若 `docs/spec/*.md` 与 `src/**` 冲突，应以 `src/**` 为准；若文档声称某行为已成立但 `test/**` 没有直接证据，则该表述必须退回为“代码存在”或“本地依赖边界”。

## 6. 当前可保守确认的缺口

从当前仓库证据面看，至少存在以下可保守记录的缺口：

- adapter 覆盖不均衡。Aave、Ether.fi、Lido 的部分变体有测试，但 Sky、Ethena、Lista、generic L2 oracle-backed 变体缺少同等级直接测试。
- 部署脚本与运行时主流程之间缺少正式的 end-to-end 部署后验证证据；目前更多是脚本可读性证据。
- Oracle 侧当前直接测试主要集中在“非正数 answer 要拒绝”和个别 L2 wrappable path；并未形成所有 oracle-backed adapter 的统一集成验证。
- 外部系统交互当前主要通过本地 interface 与 mock 说明边界；不能仅凭接口命名推断外部协议完整语义。

## 7. 读者使用建议

阅读规格集时，可以按以下方式判定证据强度：

1. 先看 `protocol.md` 和 `implementation-map.md` 确认表面边界。
2. 再看本文判断该表面属于“直接测试”“部分测试”还是“主要代码证据”。
3. 对于后两类表面，继续回到对应 `src/**` 文件核实，不把文档文字本身视为最终证明。
