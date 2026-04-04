# Common Foundations

## 目标

本文档只基于以下当前实现与相关测试，整理会持续影响上层产品语义的基础层规则：

- `src/libraries/TokenHelper.sol`
- `src/libraries/ReentrancyGuard.sol`
- `src/libraries/SYUtils.sol`
- `src/assets/base/OutrunERC20.sol`
- `src/assets/base/OutrunERC20Pausable.sol`
- `src/assets/omnichain/OutrunOFT.sol`
- `src/libraries/oracle/OutrunExchangeOracleAdapter.sol`
- `test/yield/SYBaseDeposit.t.sol`
- `test/yield/OutrunWeETHSY.t.sol`
- `test/yield/OutrunL2WrappableWstETHSY.t.sol`
- `test/support/MockOracleWarnings.t.sol`
- `test/assets/OutrunUniversalAssets.t.sol`

本文档只描述当前代码已经实现并能从这些本地真源直接观察到的行为，不包含 roadmap、推测中的协议规则，也不把外部系统行为升级为仓库已证事实。

## Native / ERC20 统一资金语义

`TokenHelper` 把 `address(0)` 定义为 `NATIVE`，因此上层只要沿用该约定，就能把 native coin 与 ERC20 放进同一套入金、出金和余额查询接口里。

`_transferIn(token, from, amount)` 的当前语义很严格：

- 当 `token == NATIVE` 时，要求 `msg.value == amount`，否则回退 `NativeAmountMismatch()`。
- 当 `token != NATIVE` 时，要求 `msg.value == 0`，然后仅在 `amount != 0` 时执行 `safeTransferFrom(from, address(this), amount)`。

`test/yield/SYBaseDeposit.t.sol` 已直接证明两点：

- ERC20 输入如果同时携带 `msg.value` 会回退。
- native 输入且 `msg.value` 与 `amount` 相等时可以成功入金。

`_transferOut(token, to, amount)` 也统一了出金语义：

- `amount == 0` 直接返回，不做外部调用。
- native 通过低级 `call` 发送，失败回退 `NativeTransferFailed()`。
- ERC20 通过 `safeTransfer` 发送。

`_selfBalance` 则把“本合约持有的 native 余额”与“本合约持有的 ERC20 余额”抽象成统一查询接口。`_wrap_unwrap_ETH` 进一步把 native 与 WETH 类资产之间的包裹/解包也纳入同一层基础工具：`tokenIn == NATIVE` 时走 `deposit`，否则走 `withdraw`。

这意味着上层产品在处理 `tokenIn` / `tokenOut` 时，不只是“支持两类资产”，而是被底层强制要求遵守同一套 `address(0) + msg.value` 资金契约。

## Approval 与 allowance 语义

`OutrunERC20` 的 allowance 语义遵循一套对上层集成很关键的当前实现规则：

- `approve(spender, value)` 直接覆盖 `owner -> spender` 的 allowance。
- `transferFrom(from, to, value)` 先调用 `_spendAllowance`，再执行 `_transfer`。
- 如果当前 allowance 等于 `type(uint256).max`，`_spendAllowance` 不会递减它；这在当前实现里等价于 infinite approval。
- 非 infinite allowance 被消耗时，会更新剩余额度，但 `_spendAllowance` 路径默认不再额外发出 `Approval` 事件。

`TokenHelper` 在此基础上又补了一层“集成友好”的 approval 语义：

- `_safeApprove` 使用 `forceApprove`，显式照顾“必须先归零再改额度”的 token。
- `_safeApproveInf` 只在当前 allowance 低于 `LOWER_BOUND_APPROVAL` 时才重置为 `0` 再设成 `type(uint256).max`。
- 这个 lower bound 被固定为 `type(uint96).max / 2`，直接体现了当前实现对“部分 token approval 只有 96 bit 有效”的兼容假设。
- native 资产不会进入 approval 流程，`_safeApproveInf` 对 `NATIVE` 直接返回。

`test/yield/OutrunWeETHSY.t.sol` 说明这层语义会实际渗透到上层路径：当 SY 把 `eETH` 包装成 `weETH` 时，测试最终断言 `eETH.allowance(address(sy), address(weETH)) > 0`，表明当前实现确实会在适配器路径里保留可继续使用的下游 allowance。

因此，上层产品语义并不是“每次操作都重新逐笔授权”，而是建立在“有限授权可递减、无限授权可持久、某些集成可自动补无限授权”的底层行为之上。

## Reentrancy 语义

`ReentrancyGuard` 的实现非常直接：

- 通过一个 `transient` 的 `locked` 布尔值表示当前调用上下文是否已进入受保护区。
- `nonReentrant` 在函数体前执行 `_nonReentrantBefore()`，在函数体后执行 `_nonReentrantAfter()`。
- 如果进入时 `locked == true`，立即回退 `ReentrancyGuardReentrantCall()`。

这层语义的重点不是“库里有 guard”，而是 guard 的碰撞边界会直接改变上层可行控制流。

`test/yield/SYBaseDeposit.t.sol` 已给出两个直接证据：

- 当前 `SYBase` 路径里，native redeem 向接收方转账后，如果接收方在回调里尝试再次进入 `redeem`，内层调用会被 `ReentrancyGuardReentrantCall()` 阻断，而外层 redeem 仍可成功完成。
- 一个把 `_transferOut` 再包进额外 `nonReentrant` helper 的 legacy 测试合约会发生“自碰撞”，说明如果同一条正常业务路径重复叠加 guard，当前实现会把它当成重入处理。

因此，上层设计不能把 guard 只当作安全装饰；在当前实现里，它同时定义了哪些回调场景是“允许外层完成、拒绝内层再入”，以及哪些内部封装方式会直接把合法流程锁死。

## 汇率与换算基础

`SYUtils` 把 `1e18` 固定为统一换算基准 `ONE`，并提供四个基础换算函数：

- `syToAsset(exchangeRate, syAmount)`：向下取整。
- `syToAssetUp(exchangeRate, syAmount)`：向上取整。
- `assetToSy(exchangeRate, assetAmount)`：向下取整。
- `assetToSyUp(exchangeRate, assetAmount)`：向上取整。

这代表当前实现里的 SY/asset 换算不是“抽象上的比例关系”，而是明确落在 18-decimal 标准化比例和整数舍入规则之上。上层只要依赖这些函数，最终就会受到“向下还是向上取整”的直接影响。

`OutrunExchangeOracleAdapter` 又把外部 oracle 的原始答案变成这套换算体系可消费的标准化汇率：

- 构造时固定 `oracle`、目标 `decimals` 与 `rawDecimals`。
- `getExchangeRate()` 只读取 `latestAnswer()`。
- 只有当答案严格大于 `0` 时才会继续执行，否则回退 `InvalidOracleAnswer()`。
- 返回值通过 `(uint256(answer) * 10 ** decimals) / 10 ** rawDecimals` 归一化到目标精度。

两组测试已经证明这层行为：

- `test/support/MockOracleWarnings.t.sol` 证明答案为 `0` 或负数时会回退。
- `test/yield/OutrunL2WrappableWstETHSY.t.sol` 证明原始 27 位精度的 `1.5e27` 会被标准化成 `1.5e18`，并被上层 SY 直接作为当前 `exchangeRate()` 使用。

所以，上层产品里任何“价值”“份额”“可铸造数量”“可赎回数量”的判断，最终都依赖两层基础事实：先把外部答案规范成目标精度，再按 `SYUtils` 的整数舍入规则完成换算。

## 资产层与 pause/flash 能力

`OutrunERC20` 把 transfer、mint、burn 全部收敛进 `_update(from, to, value)`，并在同一个入口前后暴露 `_beforeTokenTransfer` / `_afterTokenTransfer` hook。当前实现里：

- `from == address(0)` 表示 mint。
- `to == address(0)` 表示 burn。
- 其余情况表示普通转账。
- `transfer`、`transferFrom`、`_mint`、`_burn` 最终都会回到 `_update`。

`OutrunERC20Pausable` 正是利用这个收敛点，把 `_update` 包上 `whenNotPaused`。这带来一个很强的当前语义：一旦 pause，不只是“普通转账暂停”，而是所有走 `_update` 的 transfer、mint、burn 都会一起受阻；而 `pause()` / `unpause()` 仅允许 owner 调用。

`OutrunOFT` 则把当前资产层进一步扩展成带 omnichain 和 flash surface 的资产基类：

- `token()` 返回 `address(this)`，表明当前 OFT 与其 ERC20 实现是同一合约。
- `approvalRequired()` 返回 `false`，表明当前 OFT 发送自身代币不要求额外先对独立 token 合约做 approval。
- `flashFeeReceiver` 可在构造时设置，也可由 owner 后续修改。
- `_flashFeeReceiver()` 直接返回这个地址，因此 flash 费用去向在当前实现里是一个显式可配置状态。
- `_debit()` 在源链侧 burn `amountSentLD`。
- `_credit()` 在目标侧 mint `_amountLD`；若接收方为零地址，则改记到 `address(0xdead)`。
- `_toSD()` 会把本地精度数量除以 `decimalConversionRate` 后压到 `uint64` 共享精度；如果超出范围，不截断，直接回退 `AmountSDOverflowed(...)`。

`test/assets/OutrunUniversalAssets.t.sol` 证明了这层资产能力在当前派生实现里的几个结果：

- flash loan 的还款路径需要 borrower 预先提供足够 allowance，否则调用回退。
- 当 `flashFeeReceiver == address(0)` 时，flash fee 会被烧掉；测试结束后 `totalSupply()` 回到 `0`。
- 配置 `flashFeeReceiver` 后，flash fee 会累计到该地址。
- 构造参数和 owner setter 都能决定当前 fee receiver。
- 跨链报价路径如果共享精度数量溢出，会按 `AmountSDOverflowed(...)` 回退。

因此，资产层不是单纯“一个 ERC20 包装壳”。在当前实现里，它同时决定了供应如何铸烧、何时可暂停、flash fee 归属给谁，以及本地数量何时还能被编码进 omnichain 消息。

## Omnichain / oracle 基础边界

这两层的共同点是：它们会强烈影响上层行为，但本仓库当前只覆盖了其中一部分本地语义。

对 `OutrunOFT` 而言，本地代码当前只直接承诺以下内容：

- 本地 token 余额如何在 `_debit` 时 burn、在 `_credit` 时 mint。
- 零地址接收方会被改写成 `address(0xdead)`。
- 本地精度到共享精度的转换规则，以及溢出时直接回退。

但它没有在这些允许源码里自行证明以下事项：

- 对端链消息一定送达。
- peer、endpoint、delegate 的配置一定正确。
- 远端实际收到的数量一定等于上游系统宣称的数量。

对 `OutrunExchangeOracleAdapter` 而言，当前实现的设计意图是作为薄层适配器，职责仅限于：

- 读取 `latestAnswer()`。
- 要求答案严格大于 `0`。
- 按 `rawDecimals -> decimals` 做一次定点归一化。

该 adapter **不实现** freshness check、heartbeat、deviation bounds、fallback oracle 或多源聚合等价格安全机制。这是明确的设计选择：

- adapter 的职责是”读取外部价格并标准化”，不是”验证价格安全性”。
- 价格可靠性保障（如 heartbeat、deviation bounds）由 Chainlink oracle 网络自身提供。
- 如需额外的价格安全机制，应由上层业务逻辑或部署时配置的 oracle 合约负责，而非 adapter 层。

所以，omnichain 与 oracle 在当前仓库中都应被视为”本地合约会消费的外部边界”。本地代码给出了消费方式，但没有把外部系统本身的正确性变成可由本仓库单独证明的事实。

## 为什么这些基础层会影响上层产品语义

这些基础层之所以重要，是因为上层 staking、router、yield、position 并不是在一张白纸上定义业务规则，而是在继承以下已经固定的底层约束：

1. 资金入口先被 `TokenHelper` 统一成 `NATIVE`/ERC20 双态语义，决定了什么样的 `msg.value` 组合是合法调用。
2. allowance 先被 `OutrunERC20` 和 `TokenHelper` 定义成“有限额度可递减、无限额度可常驻、部分路径会自动补无限授权”，决定了上层集成是一次性授权还是长生命周期授权。
3. 外部回调安全性先被 `ReentrancyGuard` 定义，决定了哪些 callback 场景只是拦住内层再入，哪些内部封装会把主路径一起锁死。
4. 价值换算先被 `SYUtils` 的 18 位比例和舍入规则固定，再叠加 oracle 归一化逻辑，直接影响份额、资产、债务和赎回数量。
5. 资产供给先被 `OutrunERC20` / `OutrunERC20Pausable` / `OutrunOFT` 的铸烧、暂停、flash fee、共享精度边界所限制，决定了上层什么时候还能转、还能 mint、还能跨链编码、还能从 flash 路径回收费用。
6. oracle 与 omnichain 都是“消费外部系统”的基础适配层；一旦上层把它们的输出当作产品判断依据，上层产品语义就天然继承了这些边界条件和未覆盖项。

换句话说，上层产品语义不是单独存在的说明书，而是这些基础层语义叠加后的结果。只要底层的资金、授权、重入、汇率、暂停、flash、跨链或 oracle 边界发生变化，上层可见行为就会一起变化。
