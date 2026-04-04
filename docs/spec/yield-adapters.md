# OutStakeV2 Yield Adapters

## 1. 文档目的

本文档汇总 `OutStakeV2` 当前 yield adapter 实现的统一行为、各协议接线方式，以及当前测试已经直接覆盖和仍未覆盖的范围。本文只基于以下本地真源整理：`src/yield/SYBase.sol`、`src/yield/OutrunL2StakedTokenSY.sol`、`src/yield/adapters/**`、`src/integrations/**/interfaces/*.sol`、`src/libraries/oracle/OutrunExchangeOracleAdapter.sol`、`src/libraries/oracle/interfaces/IExchangeRateOracle.sol` 与相关测试。

## 2. 统一 `SYBase` 行为

`SYBase` 是所有当前 adapter 的统一外壳，负责 share token 的铸造、销毁、暂停控制和基础入金/出金流程。

- 构造阶段要求 `yieldBearingToken` 非零地址，并直接继承该 token 的 `decimals` 作为 SY share 精度。
- `deposit()` 带有 `nonReentrant` 和 `whenNotPaused` 修饰；先校验 `tokenIn` 是否有效、入金数量非零，再拒绝“ERC20 输入同时携带 `msg.value`”的路径。
- `deposit()` 随后调用 `_transferIn()` 拉取资产，再进入 adapter 自己的 `_deposit()` 逻辑，最后检查 `minSharesOut`、给 `receiver` 铸造 shares，并发出 `Deposit` 事件。
- `redeem()` 同样带有 `nonReentrant` 和 `whenNotPaused` 修饰；先校验 `tokenOut` 和 share 数量，再进入 adapter 自己的 `_redeem()`，之后根据 `burnFromInternalBalance` 决定从 `address(this)` 或 `msg.sender` 销毁 shares，检查 `minTokenOut`，并发出 `Redeem` 事件。
- `previewDeposit()` / `previewRedeem()` 只做 token 有效性校验，再转发到 adapter 的 `_previewDeposit()` / `_previewRedeem()`。
- `exchangeRate()`、`getTokensIn()`、`getTokensOut()`、`isValidTokenIn()`、`isValidTokenOut()` 全部留给具体 adapter 决定。

当前基础测试证据来自 `test/yield/SYBaseDeposit.t.sol`：

- 已覆盖 ERC20 输入携带 `msg.value` 会 revert。
- 已覆盖 native 输入在匹配 `msg.value` 的场景下可成功 mint shares。
- 已覆盖当前 `redeem()` 外层 `nonReentrant` 能阻断 native 回调重入，同时外层赎回仍可成功。
- 已覆盖“旧式在内部 transfer-out 再套一层 `nonReentrant`”会自碰撞，这解释了当前 base 只在外层入口加 guard 的行为。

## 3. Aave adapter

`OutrunAaveV3SY` 对应 Aave V3 aToken 适配。

- `yieldBearingToken` 是 aToken，`underlying` 在构造时通过 `IAToken(_aToken).UNDERLYING_ASSET_ADDRESS()` 读取。
- 入金支持 `underlying` 和 aToken 本身。
- 当 `tokenIn == underlying` 时，adapter 先无限授权给 `aavePool`，再调用 `IAaveV3Pool.supply(underlying, amountDeposited, address(this), 0)`。
- 当 `tokenIn == yieldBearingToken` 时，不走 Aave `supply()`，直接把收到的 aToken 作为现成仓位处理。
- 无论输入是哪条路径，shares 都通过 `AaveAdapterLib.calcSharesFromAssetUp(amountDeposited, normalizedIncome)` 计算。
- 赎回时先用 `AaveAdapterLib.calcSharesToAssetDown(amountSharesToRedeem, normalizedIncome)` 计算 `amountTokenOut`。
- 当 `tokenOut == underlying` 时，调用 `IAaveV3Pool.withdraw(underlying, amountTokenOut, receiver)`；否则直接把 aToken 转给 `receiver`。
- `exchangeRate()` 读取 `getReserveNormalizedIncome(underlying)`，再除以 `1e9`，把 Aave 的 27 位精度归一到 18 位。
- `assetInfo()` 把 canonical asset 暴露为 `underlying`。

当前测试覆盖只看到 `test/yield/OutrunAaveV3SY.t.sol`：

- 已覆盖 `previewRedeem(aToken)` 与实际 `redeem(aToken)` 在完整 normalized income 精度下保持一致。
- 未看到 `deposit(underlying)`、`deposit(aToken)`、`redeem(underlying)`、`exchangeRate()`、`getTokensIn/Out()` 的直接测试。

## 4. Ether.fi adapter

`OutrunWeETHSY` 对应 Ether.fi 的 `weETH` 适配。

- 入金支持 `NATIVE`、`EETH`、`weETH`。
- 当 `tokenIn == NATIVE` 时，调用 `IDepositAdapter.depositETHForWeETH{value: amountDeposited}(address(0))`，当前实现固定走 `address(0)` referral。
- 当 `tokenIn == EETH` 时，先对 `weETH` 无限授权，再调用 `IWeETH.wrap(amountDeposited)`。
- 当 `tokenIn == weETH` 时，shares 为 1:1。
- 赎回支持 `EETH` 和 `weETH`，不支持 native ETH 直出。
- 当 `tokenOut == EETH` 时，调用 `IWeETH.unwrap(amountSharesToRedeem)`，再把 eETH 转给接收者；当 `tokenOut == weETH` 时，直接 1:1 转出。
- `exchangeRate()` 使用 `ILiquidityPool.amountForShare(1 ether)` 作为 `eETH / weETH` 汇率。
- `previewDeposit(NATIVE)` 当前实现经由 `sharesForAmount()` 和 `amountForShare()` 组合报价；`previewDeposit(EETH)` 直接用 `sharesForAmount()`；`previewRedeem(EETH)` 用 `amountForShare()`。
- `assetInfo()` 对外声明 canonical asset 为 `NATIVE`，精度 18。

当前测试覆盖只看到 `test/yield/OutrunWeETHSY.t.sol`：

- 已覆盖 `deposit(EETH)` 会授权给 `weETH` 并成功 wrap。
- 未看到 native deposit、两条 redeem 路径、preview 系列和 `exchangeRate()` 的直接测试。

## 5. Lido L1 / L2 adapters

当前 Lido 相关实现包含三个 adapter：`OutrunWstETHSY`、`OutrunL2WstETHSY`、`OutrunL2WrappableWstETHSY`。

### `OutrunWstETHSY`（L1）

- 入金支持 `NATIVE`、`STETH`、`wstETH`。
- 当 `tokenIn == NATIVE` 时，先调用 `IStETH.submit{value: amountDeposited}(address(0))`，当前实现固定 no-referral；然后把返回的 stETH shares 再经 `getPooledEthByShares()` 转回 token 数量后送入 `IWstETH.wrap()`。
- 当 `tokenIn == STETH` 时，先授权再直接 `wrap(amountDeposited)`。
- 当 `tokenIn == wstETH` 时，shares 为 1:1。
- 赎回支持 `STETH` 和 `wstETH`；当 `tokenOut == STETH` 时，调用 `unwrap()` 后把 stETH 转出。
- `exchangeRate()` 直接读取 `IWstETH.stEthPerToken()`。
- `previewDeposit(NATIVE/STETH)` 当前实现使用 `IStETH.getSharesByPooledEth()`；`previewRedeem(STETH)` 使用 `IStETH.getPooledEthByShares()`。
- `assetInfo()` 把 canonical asset 暴露为 `STETH`。

`test/yield/OutrunWstETHSY.t.sol` 目前只直接证明：

- native deposit 会走 `submit(address(0))`，即当前代码显式使用 no-referral 路径。

### `OutrunL2WstETHSY`（L2 oracle-backed, non-wrappable）

- 只接受 `wstETH` 入金，也只支持 `wstETH` 赎回。
- `_deposit()`、`_redeem()`、`_previewDeposit()`、`_previewRedeem()` 全部是 1:1。
- `exchangeRate()` 不从 token 本身读，而是直接调用外部 `IExchangeRateOracle(oracle).getExchangeRate()`。
- `assetInfo()` 不暴露 L2 token 本地语义，而是暴露构造时传入的“Ethereum 上 canonical underlying 地址和精度”。

当前未看到该合约的独立测试文件。

### `OutrunL2WrappableWstETHSY`（L2 oracle-backed, wrappable）

- 同时支持 `STETH` 和 `wstETH` 双向进出。
- 当前实现中，当 `tokenIn == STETH` 时调用 `IL2StETH(STETH).unwrap(amountDeposited)` 来得到 shares；当 `tokenOut == STETH` 时则先授权 `wstETH` 给 `STETH` 合约，再调用 `IL2StETH(STETH).wrap(amountSharesToRedeem)`，最后把 `STETH` 转给接收者。
- 当输入或输出是 `wstETH` 本身时，都是 1:1。
- `exchangeRate()` 走 `EXCHANGE_RATE_ORACLE.getExchangeRate()`。
- `previewDeposit(STETH)` 使用 `getSharesByTokens()`；`previewRedeem(STETH)` 使用 `getTokensByShares()`。
- `assetInfo()` 同样返回 Ethereum 上 canonical underlying 的地址和精度。

`test/yield/OutrunL2WrappableWstETHSY.t.sol` 已直接覆盖：

- `redeem(STETH)` 会把转换后的 token 发给接收者。
- `redeem(wstETH)` 会直接把 wrapped token 发给接收者。
- `exchangeRate()` 会使用经过 `OutrunExchangeOracleAdapter` 归一化后的 oracle 值。

## 6. Lista adapter

`OutrunSlisBNBSY` 对应 Lista 的 `slisBNB` 适配，除了普通 deposit/redeem 之外还绑定 provider 委托关系。

- 入金支持 `NATIVE` 和 `slisBNB`。
- 当 `tokenIn == NATIVE` 时，调用 `listaBNBStakeManager.deposit{value: amountDeposited}()`，再用 `convertBnbToSnBnb(amountDeposited)` 计算 shares。
- 当 `tokenIn == slisBNB` 时，shares 为 1:1。
- 无论哪条入金路径，当前实现都会在 `_deposit()` 末尾把 `amountSharesOut` 授权并调用 `slisBNBProvider.provide(amountSharesOut, delegateTo)`。
- 赎回只允许 `slisBNB` 路径；`_redeem()` 直接调用 `slisBNBProvider.release(receiver, amountSharesToRedeem)`，返回值也按 1:1 处理。
- `exchangeRate()` 使用 `convertSnBnbToBnb(1 ether)`，即把 1 个 `slisBNB` 份额映射回 BNB。
- `updateDelegateTo()` 只有 owner 能调用；当前实现会先按 `totalSupply` 从 provider `release(address(this), totalSupply)`，再把同样数量重新 `provide(totalSupply, _delegateTo)`，然后才更新存储里的 `delegateTo`。
- `assetInfo()` 对外声明 canonical asset 为 `NATIVE`，精度 18。

当前未看到 `OutrunSlisBNBSY` 的独立测试文件。

## 7. Sky / Ethena adapters

### `OutrunStakedUsdsSY`（Sky L1）

- 把 `sUSDS` 当作 `yieldBearingToken`，`USDS` 当作 underlying。
- 入金支持 `USDS` 和 `sUSDS`；当 `tokenIn == USDS` 时，调用 `IERC4626(yieldBearingToken).deposit(amountDeposited, address(this))`。
- 赎回支持 `USDS` 和 `sUSDS`；当 `tokenOut == USDS` 时，调用 `IERC4626(yieldBearingToken).redeem(amountSharesToRedeem, receiver, address(this))`。
- `exchangeRate()` 使用 `convertToAssets(1 ether)`。
- preview 路径分别使用 `previewDeposit()` 和 `previewRedeem()`。
- `assetInfo()` 对外声明 canonical asset 为 `USDS`，精度 18。

### `OutrunL2StakedUsdsSY`（Sky L2）

- 同时支持 `USDC`、`USDS`、`sUSDS` 三种输入和输出。
- 当输入不是 `sUSDS` 时，当前实现一律通过 `IPSM3.swapExactIn(tokenIn, yieldBearingToken, amountDeposited, 0, address(this), 0)` 进入 `sUSDS`。
- 当输出不是 `sUSDS` 时，当前实现一律通过 `IPSM3.swapExactIn(yieldBearingToken, tokenOut, amountSharesToRedeem, 0, receiver, 0)` 兑出。
- `exchangeRate()` 直接用 `previewSwapExactIn(sUSDS, USDS, 1 ether)` 作为份额价格。
- preview 路径同样完全依赖 `IPSM3.previewSwapExactIn()`。
- `assetInfo()` 对外声明 canonical asset 为 `USDS`，精度 18。

### `OutrunStakedUSDeSY`（Ethena）

- 把 `sUSDe` 当作 `yieldBearingToken`，`USDE` 当作 underlying。
- 入金支持 `USDE` 和 `sUSDe`；当 `tokenIn == USDE` 时，调用 `IERC4626(yieldBearingToken).deposit(amountDeposited, address(this))`。
- 赎回只支持 `sUSDe` 本身，不支持把 shares 直接兑回 `USDE`。
- `_redeem()` 只有 1:1 转出 `sUSDe` 路径；`previewRedeem()` 也是纯 1:1。
- `exchangeRate()` 使用 `convertToAssets(1 ether)`。
- `assetInfo()` 对外声明 canonical asset 为 `USDE`，精度 18。

当前未看到上述三个 adapter 的独立测试文件。

## 8. Generic L2 oracle-backed adapter

`OutrunL2StakedTokenSY` 是当前仓库里最通用的 L2 oracle-backed SY 形态。

- 它只接受 `yieldBearingToken` 本身入金，也只把 `yieldBearingToken` 本身赎回。
- `_deposit()`、`_redeem()`、`_previewDeposit()`、`_previewRedeem()` 全部是严格 1:1，不做任何 wrap、unwrap 或 swap。
- `exchangeRate()` 不从 token 合约读取，而是读取外部 `exchangeRateOracle` 的 `getExchangeRate()`。
- `assetInfo()` 返回的是构造时传入的 Ethereum canonical underlying 地址和精度，而不是从 L2 token 动态推导。

当前仓库里与这类 adapter 配套的公共 oracle 适配器是 `OutrunExchangeOracleAdapter`：

- 构造时记录原始聚合器地址、目标输出精度 `decimals` 和聚合器原始精度 `rawDecimals`。
- `getExchangeRate()` 读取 `latestAnswer()`，若答案小于等于 0 则以 `InvalidOracleAnswer()` revert。
- 正常情况下会按 `(uint256(answer) * 10 ** decimals) / 10 ** rawDecimals` 归一化输出。

该 adapter 的设计意图是作为薄层适配器，只负责读取 Chainlink 价格并标准化精度。它不实现 freshness check、heartbeat、deviation bounds、fallback oracle 或多源聚合等价格安全机制——这些由 Chainlink oracle 网络自身保障。如需额外的价格安全机制，应由上层业务逻辑或部署时配置的 oracle 合约负责。

相关测试证据：

- `test/yield/OutrunL2WrappableWstETHSY.t.sol` 证明 oracle answer 可从 27 位精度归一到 18 位后供 adapter 使用。
- `test/support/MockOracleWarnings.t.sol` 证明 `OutrunExchangeOracleAdapter` 在 answer 为 0 或负数时会 revert。
- 当前未看到 `OutrunL2StakedTokenSY` 本身的独立测试文件。

## 9. 当前测试覆盖与缺口

目前有直接测试证据的 yield adapter 相关表面主要是：

- `SYBase` 的 ERC20/native 输入 guard 与 redeem 重入保护。
- `OutrunAaveV3SY` 的 `previewRedeem` 与 `redeem(aToken)` 精度一致性。
- `OutrunWeETHSY` 的 `deposit(EETH)` wrap 路径。
- `OutrunWstETHSY` 的 native deposit no-referral 行为。
- `OutrunL2WrappableWstETHSY` 的两条 redeem 路径和 oracle 归一化汇率。
- `OutrunExchangeOracleAdapter` 的“非正数 answer 必须 revert”约束。

仍然明显缺口的部分包括：

- `OutrunL2StakedTokenSY`、`OutrunL2WstETHSY`、`OutrunSlisBNBSY`、`OutrunStakedUsdsSY`、`OutrunL2StakedUsdsSY`、`OutrunStakedUSDeSY` 没有同名独立测试文件。
- 多数 adapter 的 `getTokensIn()`、`getTokensOut()`、`isValidTokenIn()`、`isValidTokenOut()`、`assetInfo()` 没有直接测试。
- Aave、Ether.fi、Sky、Ethena、Lista 的大部分 deposit/redeem 双向路径仍主要依赖源码阅读，而非现成测试证明。
- oracle-backed adapter 的统一覆盖仍不足；当前直接证据主要集中在 `OutrunL2WrappableWstETHSY` 和 `OutrunExchangeOracleAdapter`，不能替代所有 L2 变体的行为证明。
