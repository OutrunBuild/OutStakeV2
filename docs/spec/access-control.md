# Access Control

## 目标

本文只基于以下本地真源整理当前实现中的访问控制边界：

- `src/assets/base/OutrunUniversalAssets.sol`
- `src/position/OutrunStakingPosition.sol`
- `src/router/OutrunRouter.sol`
- `src/yield/SYBase.sol`
- `src/assets/base/OutrunERC20Pausable.sol`
- 相关测试：`test/assets/OutrunUniversalAssets.t.sol`、`test/position/OutrunStakingPosition.t.sol`、`test/router/OutrunRouter.t.sol`、`test/yield/SYBaseDeposit.t.sol`

本文不讨论 roadmap，不推断未落地治理流程，也不把外部集成假设扩展成权限结论。

## `uAsset` 权限边界

`OutrunUniversalAssets` 继承 `Ownable`，当前只有 owner 能执行：

- `setMintingCap(address minter, uint256 mintingCap)`
- `revokeMinter(address minter)`
- `setOutboundRateLimit(uint32 dstEid, uint256 limit, uint256 window)`
- `setInboundRateLimit(uint32 srcEid, uint256 limit, uint256 window)`
- `removeOutboundRateLimit(uint32 dstEid)`
- `removeInboundRateLimit(uint32 srcEid)`

测试已覆盖：

- 非 owner 调用 owner 入口会因 `OwnableUnauthorizedAccount` 回退
- owner 调整 cap 后，minter 的可 mint 额度会随之变化
- owner 撤销 minter 后，该地址不能继续 mint
- 非 owner 不能设置或移除 OFT inbound / outbound 速率限制
- owner 移除某个 peerEid 的单向速率限制后，该方向不再按本地 limiter 限速

公共入口方面：

- `checkMintableAmount(minter)`：任何人可读
- `mint(receiver, amount)`：任何地址都可以发起调用，但只有 `msg.sender` 自己在 `mintingStatusTable` 中仍有剩余额度时才会成功
- `repay(account, amount)`：任何地址都可以发起调用，冲减 `msg.sender` 自己名下的 `amountInMinted`；同时消耗 `account → msg.sender` 的 allowance（amount 数量的 uAsset 从 account 转给 msg.sender 用于 burn）。调用者必须持有足够的 uAsset 来 burn。

这意味着当前 `uAsset` 没有单独的 `minter role` 合约模块，真正的 mint 权限边界是“是否被 owner 配置了 cap”。`test/assets/OutrunUniversalAssets.t.sol` 还证明了旧的单参数 `burn(uint256)` 入口不存在；公共调用者不能绕过 `repay` 路径直接销毁债务。

OFT 速率限制入口来自 `OutrunOFT` 继承面，并通过 `OutrunUniversalAssets` 暴露。它们不改变 `mintingStatusTable` 的生命周期债务记账，只约束指定 peerEid 与方向上的跨链流速。`window == 0` 不能通过 set 入口配置；要清除某方向限速必须使用对应 `remove*RateLimit` 入口。

## `OutrunStakingPosition` 权限边界

`OutrunStakingPosition` 里有三类受限角色：owner、position owner、keeper。

owner 当前能执行：

- `pause()`
- `unpause()`
- `setMinStake(uint256)`
- `setUAsset(address)`
- `setRevenuePool(address)`
- `setKeeper(address)`
- `harvestWrapYield(address tokenOut)`

position owner 由 `positions[positionId].owner` 决定，只有该地址能执行：

- `drawUAsset(uint256 positionId, address recipient)`
- `redeem(uint256 positionId, uint256 syRedeemed, address receiver, address tokenOut)`

keeper 由 `keeper` 状态变量决定，只有该地址能执行：

- `keepRedeem(uint256 positionId, uint256 amountInUAsset, address receiver)`

公共调用者开放的入口包括：

- `previewStake`
- `previewWrapStake`
- `previewDrawUAsset`
- `previewRedeem`
- `previewWrapRedeem`
- `stake`
- `wrapStake`
- `wrapRedeem`

但这些入口是否成功，仍受当前实现约束：

- `stake`、`wrapStake`、`drawUAsset`、`redeem`、`wrapRedeem`、`keepRedeem` 都受 `whenNotPaused` 保护
- `stake` 和 `wrapStake` 依赖 `uAsset.checkMintableAmount(address(this))`，所以 position 合约本身必须先在 `uAsset` 上被授予足够 cap
- `redeem`、`wrapRedeem`、`keepRedeem` 最终都走 `uAsset.repay(...)`，所以调用者还必须持有足够的 `uAsset`，并给 position 合约足够 allowance

测试已证明：

- 非仓位 owner 调用 `drawUAsset` 会触发统一的 `PositionAccessDenied`
- owner 替换 keeper 后，旧 keeper 失权，新 keeper 获得 `keepRedeem` 权限
- `harvestWrapYield` 会把 wrap 池中高于债务等价部分的收益转给 `revenuePool`
- `positionOwner` 和 `uAssetReceiver` 可以是不同地址，说明仓位控制权与初始收款地址是分离的

## `OutrunRouter` 权限边界

`OutrunRouter` 继承 `Ownable`，当前唯一的 owner 入口是：

- `setMemeverseLauncher(address)`

除这一项外，router 的业务入口都对公共调用者开放，包括：

- `mintSYFromToken`
- `redeemSyToToken`
- `previewStakeFromToken`
- `previewStakeFromSY`
- `previewWrapStakeFromToken`
- `stakeFromToken`
- `stakeFromSY`
- `wrapStakeFromToken`
- `wrapStakeFromSY`
- `previewWrapRedeem`
- `wrapRedeem`
- `genesisByToken`
- `genesisBySY`

当前实现里，router 没有 pause、allowlist、keeper、per-user 管理员名单等额外权限层。它更像公开组合入口，真正的边界来自：

- router 会从 `msg.sender` 拉取 token、SY 或 `uAsset`
- 用户必须预先提供余额和 allowance
- 下游 `SY`、`OutrunStakingPosition`、`uAsset` 的校验仍然生效

测试已证明：

- `mintSYFromToken` 和 `redeemSyToToken` 使用的是调用者资金，不依赖 router 预存余额
- `wrapRedeem` 会先从调用者拉取 `uAsset`，再调用 stake manager
- `genesisBySY` 走的是锁仓 `stake` 路径，不是 `wrapStake`

## `SY` / pausable 表面的权限边界

`SYBase` 继承 `OutrunERC20Pausable`，因此当前所有基于该基类的 `SY` 至少都具有以下 owner 权限：

- `pause()`
- `unpause()`

公共调用者可用的核心入口包括：

- `deposit`
- `redeem`
- `previewDeposit`
- `previewRedeem`
- `exchangeRate`
- `getTokensIn`
- `getTokensOut`
- `isValidTokenIn`
- `isValidTokenOut`

当前实现中的关键边界如下：

- `deposit` 和 `redeem` 都受 `whenNotPaused` 保护
- `deposit` 会校验 `tokenIn` 是否有效，且 ERC20 路径下禁止携带 `msg.value`
- `redeem` 会校验 `tokenOut` 是否有效
- `redeem` 的 `burnFromInternalBalance` 参数允许调用路径在“烧掉 `address(this)` 内部持仓”和“烧掉 `msg.sender` 自身持仓”之间切换，但这不是权限升级；是否能成功仍取决于对应地址是否已有 shares

`test/yield/SYBaseDeposit.t.sol` 已证明：

- ERC20 deposit 路径携带 `msg.value` 会回退
- native deposit 路径在数值匹配时可以成功
- `redeem` 受非重入保护，回调重入会被 guard 阻断

## 公共调用者能做什么、不能做什么

公共调用者当前能做什么：

- 读取 mint cap、preview、exchange rate、position 信息等公开状态
- 在自己持有对应资产并提供 allowance 的前提下，直接使用 `SY` 的 `deposit` / `redeem`
- 通过 router 使用 stake、wrap stake、wrap redeem、genesis 等公开组合入口
- 直接调用 `OutrunStakingPosition.stake` 或 `wrapStake`
- 作为被授 cap 的 minter 调用 `uAsset.mint`
- 通过 `uAsset.repay` 偿还自己名下的 minted debt

公共调用者当前不能做什么：

- 不能修改 `uAsset` 的 mint cap
- 不能撤销其他 minter
- 不能 pause / unpause `SY` 或 `OutrunStakingPosition`
- 不能修改 `OutrunStakingPosition` 的 `minStake`、`uAsset`、`revenuePool`、`keeper`
- 不能调用不属于自己仓位的 `drawUAsset` 或 `redeem`
- 不能在不是 keeper 的情况下调用 `keepRedeem`
- 不能修改 router 的 `memeverseLauncher`
- 不能绕过 `uAsset.repay` 直接用旧 burn 入口销债

## 当前实现提醒

- `uAsset.mint` 是公开函数，但并不代表任何人都能 mint；真正决定权在 owner 设定的 `mintingCap`
- `OutrunStakingPosition` 自身要能 mint `uAsset`，前提是它先被 `uAsset` owner 配置成有额度的 minter；测试中是手动给 `address(position)` 设置了无限 cap
- `redeem`、`wrapRedeem`、`keepRedeem` 都依赖调用者先持有足够 `uAsset` 并授权给 position 合约，权限边界里包含 allowance 这一层
- `OutrunRouter` 当前只有一个 owner 配置口，没有紧急暂停或业务级 allowlist；它主要承担公开路由角色
- `SYBase` 的 pause 是 token 级总开关，暂停后不仅转账受影响，`deposit` / `redeem` 也会一起停用
- 本文只覆盖当前代码显式体现的边界；像 `memeverseLauncher`、具体 `SY` adapter、外部协议合约本身的权限模型，不在本文结论范围内
