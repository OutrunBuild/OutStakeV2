# 部署文档

## 当前部署表面

当前仓库的生产部署入口只有 upgradeable 路径：

- `script/deploy/YieldDeployScript.s.sol`
- `script/deploy/OutstakeScript.s.sol`
- `script/deploy/deployment/OutrunDeployer.sol`

`YieldDeployScript.run()` 默认执行 `_supportUpgradeableAUSDC()`，并通过 `ERC1967Proxy` 部署 `OutrunAaveV3SYUpgradeable` 与 `OutrunStakingPositionUpgradeable`。

`OutstakeScript.run()` 默认只部署 `OutrunRouter` 与基础链配置。

## 关键约束

- SY、uAsset、position 的当前产品实现都通过 proxy-backed upgradeable variants 部署。
- router 仍是非 upgradeable helper。
- oracle adapter 仍是非 upgradeable helper。
- SY deploy helper 以 upgradeable 路径为准。

## 运行时入口

部署脚本依赖环境变量注入 owner、keeper、revenuePool、router、launcher、endpoint 与外部协议地址。
`OutrunDeployer` 提供 owner-only 的 CREATE3 部署能力。
