# OutStakeV2 Oracles And Integrations

## 文档目的

本文档用于说明 `OutStakeV2` 当前仓库里与 oracle 和外部 integration 相关的已落地实现边界。本文只依据以下本地真源编写：`src/integrations/**`、`src/libraries/oracle/**`、`src/yield/adapters/**`、`test/yield/**`、`test/support/**`。

本文不引入 roadmap，不把接口命名、协议常识或外部文档升级为仓库事实。凡是本地代码或测试没有直接证明的外部行为，统一作为依赖、假设或限制描述。

## 本地 integration boundary 原则

当前仓库对外部协议的接入方式是：在 `src/integrations/**` 只保留最小 interface，在 `src/yield/adapters/**` 内做 `deposit`、`redeem`、`preview`、`exchangeRate` 与 token in/out 的本地封装。

本地实现当前只直接承诺以下内容：

- adapter 会调用哪些外部函数。
- adapter 把哪些 token 视为合法 `tokenIn` / `tokenOut`。
- `exchangeRate()` 在本地是读取哪个外部入口或 oracle 入口。
- 某些关键路径是否已有本地测试直接覆盖。

本地实现当前不单独证明以下内容：

- 外部协议真实收益来源、结算时点、暂停逻辑、升级权限、排队或手续费语义。
- 外部 wrapper / vault / PSM / provider 的真实资产安全性与活跃性。
- 某个 oracle 是否足够新鲜、是否抗操纵、是否和目标资产精确对应。

因此，阅读这些 adapter 时，应把外部协议返回值视为本地依赖输入，而不是仓库自己定义的经济规则。

## Aave

当前 Aave 相关本地边界由 `src/integrations/aave/interfaces/IAaveV3Pool.sol`、`src/integrations/aave/interfaces/IAToken.sol` 与 `src/yield/adapters/aave/OutrunAaveV3SY.sol` 构成。

本地已实现的调用关系：

- 构造时通过 `IAToken(_aToken).UNDERLYING_ASSET_ADDRESS()` 读取 `underlying`。
- `deposit` 在 `tokenIn == underlying` 时调用 `IAaveV3Pool.supply(underlying, amountDeposited, address(this), 0)`。
- `redeem` 在 `tokenOut == underlying` 时调用 `IAaveV3Pool.withdraw(underlying, amountTokenOut, receiver)`。
- `exchangeRate`、`previewDeposit`、`previewRedeem` 都依赖 `IAaveV3Pool.getReserveNormalizedIncome(underlying)`，并通过 `AaveAdapterLib` 做份额与资产换算。
- `getTokensIn` / `getTokensOut` 都只暴露 `underlying` 与 `yieldBearingToken`。

本地已验证内容：

- `test/yield/OutrunAaveV3SY.t.sol` 直接验证了在完整 `normalizedIncome` 精度下，`previewRedeem` 与 `redeem` 对 `aToken` 输出路径一致。

本地依赖与假设：

- `getReserveNormalizedIncome` 是否持续单调、是否准确代表真实资产增值，属于外部依赖。
- `supply` / `withdraw` 的真实资金流和上游 reserve 状态变化，本仓库未做集成级证明。
- 本地未看到覆盖 `tokenIn == underlying` 的真实 supply 存入测试，也未看到直接覆盖 `tokenOut == underlying` 的真实 withdraw 资金流测试。

## Ether.fi

当前 Ether.fi 相关本地边界由 `src/integrations/etherfi/interfaces/IWeETH.sol`、`IDepositAdapter.sol`、`ILiquidityPool.sol` 与 `src/yield/adapters/etherfi/OutrunWeETHSY.sol` 构成。

本地已实现的调用关系：

- `tokenIn == NATIVE` 时，`deposit` 调用 `IDepositAdapter.depositETHForWeETH{value: amountDeposited}(address(0))`。
- `tokenIn == EETH` 时，adapter 先授权 `yieldBearingToken`，再调用 `IWeETH.wrap(amountDeposited)`。
- `tokenIn == yieldBearingToken` 时，本地按 1:1 记 shares。
- `tokenOut == EETH` 时，`redeem` 调用 `IWeETH.unwrap(amountSharesToRedeem)`，随后把 `EETH` 转给 `receiver`。
- `exchangeRate` 直接读取 `ILiquidityPool.amountForShare(1 ether)`。
- `previewDeposit` / `previewRedeem` 依赖 `ILiquidityPool.sharesForAmount` 与 `amountForShare` 做报价。
- `getTokensIn` 暴露 `NATIVE`、`EETH`、`yieldBearingToken`；`getTokensOut` 暴露 `EETH`、`yieldBearingToken`。

本地已验证内容：

- `test/yield/OutrunWeETHSY.t.sol` 直接验证了 `tokenIn == EETH` 时会完成授权、调用 wrap，并把 `weETH` 留在 SY 内部。

本地依赖与假设：

- `depositETHForWeETH(address(0))` 对 `address(0)` 的 referral 语义、原生 ETH 到 weETH 的真实上游路径，属于外部依赖。
- `ILiquidityPool.amountForShare` 与 `sharesForAmount` 是否精确互逆、是否带费用，仓库未单独证明。
- 本地未看到覆盖 native deposit、EETH redeem 或 preview 与真实 redeem 对齐的直接测试。

## Lido

当前 Lido 相关本地边界分为 L1 和 L2 两组。

L1 相关文件是 `src/integrations/lido/interfaces/IStETH.sol`、`IWstETH.sol` 与 `src/yield/adapters/lido/OutrunWstETHSY.sol`。

本地已实现的 L1 调用关系：

- `tokenIn == NATIVE` 时，adapter 调用 `IStETH.submit{value: amountDeposited}(address(0))`，然后读取 `getPooledEthByShares`，再调用 `IWstETH.wrap(...)`。
- `tokenIn == STETH` 时，adapter 直接调用 `IWstETH.wrap(amountDeposited)`。
- `tokenOut == STETH` 时，adapter 调用 `IWstETH.unwrap(amountSharesToRedeem)` 并转出 `STETH`。
- `exchangeRate` 直接读取 `IWstETH.stEthPerToken()`。
- `previewDeposit` / `previewRedeem` 依赖 `IStETH.getSharesByPooledEth` 与 `getPooledEthByShares`。
- `getTokensIn` 暴露 `yieldBearingToken`、`NATIVE`、`STETH`；`getTokensOut` 暴露 `yieldBearingToken`、`STETH`。

本地已验证内容：

- `test/yield/OutrunWstETHSY.t.sol` 直接验证了 native deposit 会走 `submit(address)`，且 referral 固定为 `address(0)`，不会走其他 selector。

L2 相关文件是 `src/integrations/lido/interfaces/IL2StETH.sol`、`src/yield/adapters/lido/OutrunL2WstETHSY.sol`、`src/yield/adapters/lido/OutrunL2WrappableWstETHSY.sol`。

本地已实现的 L2 调用关系：

- `OutrunL2WstETHSY` 只接受并只赎回 `yieldBearingToken` 本身；`exchangeRate` 完全依赖外部 `IExchangeRateOracle.getExchangeRate()`。
- `OutrunL2WrappableWstETHSY` 在 `tokenIn == STETH` 时调用 `IL2StETH.unwrap(amountDeposited)`；在 `tokenOut == STETH` 时先授权 `yieldBearingToken` 给 `STETH`，再调用 `IL2StETH.wrap(amountSharesToRedeem)`，最后把 `STETH` 转给接收者。
- `OutrunL2WrappableWstETHSY` 的 `previewDeposit` / `previewRedeem` 依赖 `IL2StETH.getSharesByTokens` 与 `getTokensByShares`。
- 两个 L2 adapter 的 `assetInfo()` 都暴露“Ethereum canonical underlying”元数据，但这只是构造参数，不是仓库自行验证的跨链事实。

本地已验证内容：

- `test/yield/OutrunL2WrappableWstETHSY.t.sol` 直接验证了：
- 赎回到 `STETH` 时，receiver 收到的是 `STETH`。
- 赎回到 `wstETH` 时，receiver 收到的是 `wstETH`。
- `exchangeRate()` 使用的是经过 `OutrunExchangeOracleAdapter` 归一化后的 oracle 值。

本地依赖与假设：

- `submit(address(0))` 的无 referral 语义、`wrap` / `unwrap` 的真实换算逻辑、L2 包装资产与 Ethereum canonical asset 的真实对应关系，都是外部依赖。
- 本地未看到 `OutrunL2WstETHSY` 的独立测试。
- `OutrunL2WrappableWstETHSY` 的函数命名与资金方向存在”对 L2 wrapper 语义的本地适配假设”；仓库只证明当前调用方式可通过现有 mock 测试，不证明所有上游实现都使用同样语义。

## Sky

当前 Sky 相关本地边界分为 L1 `sUSDS` 适配和 L2 `PSM3` 适配两组。

L1 相关文件是 `src/yield/adapters/sky/OutrunStakedUsdsSY.sol`。

本地已实现的 L1 调用关系：

- `tokenIn == USDS` 时，adapter 授权 `yieldBearingToken`，然后调用 `IERC4626(yieldBearingToken).deposit(amountDeposited, address(this))`。
- `tokenOut == USDS` 时，adapter 调用 `IERC4626(yieldBearingToken).redeem(amountSharesToRedeem, receiver, address(this))`。
- `exchangeRate` 直接读取 `IERC4626(yieldBearingToken).convertToAssets(1 ether)`。
- `previewDeposit` / `previewRedeem` 直接依赖 ERC4626 preview。
- `getTokensIn` / `getTokensOut` 都暴露 `yieldBearingToken` 与 `USDS`。

L2 相关文件是 `src/integrations/sky/interfaces/IPSM3.sol` 与 `src/yield/adapters/sky/OutrunL2StakedUsdsSY.sol`。

本地已实现的 L2 调用关系：

- 除 `yieldBearingToken` 直存直取外，存入和赎回都通过 `IPSM3.swapExactIn(...)` 执行。
- `deposit` 在 `tokenIn != yieldBearingToken` 时，对 `PSM3` 做无限授权，并调用 `swapExactIn(tokenIn, yieldBearingToken, amountDeposited, 0, address(this), 0)`。
- `redeem` 在 `tokenOut != yieldBearingToken` 时，对 `PSM3` 做无限授权，并调用 `swapExactIn(yieldBearingToken, tokenOut, amountSharesToRedeem, 0, receiver, 0)`。
- `exchangeRate` 与 preview 都依赖 `IPSM3.previewSwapExactIn(...)`。
- `getTokensIn` / `getTokensOut` 都暴露 `USDC`、`USDS`、`yieldBearingToken`。

本地测试与限制：

- 当前测试目录没有 `OutrunStakedUsdsSY` 或 `OutrunL2StakedUsdsSY` 的独立正式测试。
- `test/yield/MockOutrunSUSDSSY.sol` 与 `test/support/MockSUSDSOracle.sol` 只说明测试支撑面里存在过 `sUSDS` 相关 mock；它们不是当前生产 adapter 的直接行为证明。

本地依赖与假设：

- ERC4626 `deposit` / `redeem` / `convertToAssets` 的真实经济语义属于外部依赖。
- `PSM3.swapExactIn` 与 `previewSwapExactIn` 是否始终一致、是否包含费用或权限门槛，仓库未单独证明。
- L2 adapter 目前把 `minAmountOut` 和 `referralCode` 都写死为 `0`，这是当前实现事实，不代表外部系统不会有额外语义。

## Ethena

当前 Ethena 相关本地边界由 `src/yield/adapters/ethena/OutrunStakedUSDeSY.sol` 构成。

本地已实现的调用关系：

- `tokenIn == USDE` 时，adapter 授权 `yieldBearingToken`，并调用 `IERC4626(yieldBearingToken).deposit(amountDeposited, address(this))`。
- `redeem` 不支持换回 `USDE`；它只把 `yieldBearingToken` 直接转给 `receiver`。
- `exchangeRate` 直接读取 `IERC4626(yieldBearingToken).convertToAssets(1 ether)`。
- `previewDeposit` 在 `tokenIn == USDE` 时依赖 `IERC4626.previewDeposit(amountTokenToDeposit)`。
- `previewRedeem` 固定返回 shares 本身。
- `getTokensIn` 暴露 `yieldBearingToken` 与 `USDE`；`getTokensOut` 只暴露 `yieldBearingToken`。

本地依赖与假设：

- ERC4626 vault 是否允许随时 deposit、其 `convertToAssets` 是否稳定反映真实可赎回价值，属于外部依赖。
- 当前测试目录没有 `OutrunStakedUSDeSY` 的独立正式测试，因此这里只能陈述本地代码路径。

## Oracle adapter 设计意图

当前通用 oracle 适配面在 `src/libraries/oracle/OutrunExchangeOracleAdapter.sol`。

本地已实现的行为：

- 构造时记录 `oracle`、目标 `decimals`，并从 `AggregatorInterface(_oracle).decimals()` 读取 `rawDecimals`。
- `getExchangeRate()` 直接读取 `AggregatorInterface(oracle).latestAnswer()`。
- 若 `latestAnswer <= 0`，则回退 `InvalidOracleAnswer()`。
- 否则按 `(uint256(answer) * 10 ** decimals) / 10 ** rawDecimals` 做精度归一化。

本地已验证内容：

- `test/support/MockOracleWarnings.t.sol` 直接验证了 `OutrunExchangeOracleAdapter`、`MockAUSDCOracle`、`MockSUSDSOracle` 在 answer 为 `0` 或负数时会回退。
- `test/yield/OutrunL2WrappableWstETHSY.t.sol` 直接验证了 L2 wstETH wrappable adapter 读取的是经过该 adapter 归一化后的汇率。

设计意图说明：

`OutrunExchangeOracleAdapter` 是一个薄层适配器，其职责是”读取 Chainlink 价格并标准化精度”，而非实现价格安全机制。以下特性是**有意不实现**的设计选择：

- **不检查 freshness**：不读取 `updatedAt`、`answeredInRound` 或 round 完整性。价格新鲜度由 Chainlink oracle 网络保障。
- **不实现 bounds 检查**：没有 upper/lower bound、deviation bounds 或价格偏差限制。这些检查如需要应由上层业务逻辑或部署时选用的 oracle 合约负责。
- **不提供 fallback**：没有 fallback oracle 或多源聚合机制。可靠性依赖单一 Chainlink feed。
- **信任 `latestAnswer()` 正值**：adapter 只做非正值拒绝和精度归一化，不验证价格是否合理。

这些设计选择意味着：如果部署环境需要更严格的价格安全机制（如多源验证、heartbeat 检查、价格偏差阈值），应在 adapter 之外实现或选择具备这些特性的 oracle 合约。mock oracle 测试只证明”非正值必须拒绝”，不证明真实生产 oracle 的部署、权限、更新频率或资产映射正确性。

## 当前实现提醒

1. 当前 adapter 文档能确认的是“本地如何调用外部协议”，不是“外部协议一定如何结算”。
2. 已有直接测试支撑的协议面主要集中在 Aave、Ether.fi、Lido L1、Lido L2 wrappable 和 oracle 非正值拒绝；Sky、Ethena、L2 non-wrappable Lido 目前缺少同等级正式测试。
3. 多个 adapter 把外部报价函数直接用于 `exchangeRate()` 或 preview，因此外部返回值异常会直接影响本地定价。
4. `OutrunL2StakedUsdsSY` 当前使用 `swapExactIn(..., minAmountOut = 0, referralCode = 0)`；`OutrunWeETHSY` 和 `OutrunWstETHSY` 的某些路径也把 referral 固定为 `address(0)`。这些都是当前硬编码事实。
5. `assetInfo()` 在多个跨链/L2 adapter 中暴露的是构造时给定的 canonical asset 元数据；这只是本地配置，不是仓库自行证明的跨链资产真实性。
