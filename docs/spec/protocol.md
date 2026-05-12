# OutStakeV2 Protocol Specification

## 系统目标

1. `uAsset` 作为统一债务与流通资产层
2. `SY` 作为标准化收益份额层
3. `OutrunStakingPositionUpgradeable` 作为仓位账本
4. `OutrunRouter` 作为用户入口
5. `script/deploy/**` 作为部署入口

## 当前范围

### assets

当前资产层以 `OutrunUniversalAssetsUpgradeable` 为中心，并通过 `OutrunOFTUpgradeable` 提供跨链扩展。
`OutrunOFTUpgradeable` 的 pause 阻断本地用户主动发起的 ERC20 路径和 pause 之后新发起的 outbound send；LayerZero inbound `_credit` 为避免阻塞已经在跨链流程中的代币，按设计不受 `whenNotPaused` 阻断。

### position

当前仓位层由 `OutrunStakingPositionUpgradeable` 实现，维护锁仓仓位与公共 wrap 池。

### yield

当前收益层以 `SYBaseUpgradeable` 为统一抽象。所有 SY adapters 都以 upgradeable variants 作为当前产品真源。

### router

当前路由层由 `OutrunRouter` 实现，保持非 upgradeable、可重部署 helper 语义。

### integrations

当前集成层只承担外部协议调用与 oracle 适配，不单独证明外部系统语义。

### deployment

当前部署层以 proxy-backed deployment flow 为准：先部署 implementation，再用 `ERC1967Proxy` 初始化并写入下游 wiring。

## 当前实现提醒

- `SY` 现在以 upgradeable variants 为产品真源
- `OutrunStakedUSDeSYUpgradeable` 只输出 `sUSDe`
- router 不承担独立资金池
