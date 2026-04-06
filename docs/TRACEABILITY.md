# OutStakeV2 Traceability（当前规则 -> 证据）

## 1. 说明

- 本文档追溯的是当前规则真源（`docs/spec/*.md` 与 Product Truth 支撑文档），并按需引用 `CLAUDE.md`/`docs/process/*` 的流程规则证据；不承担历史需求文档的复刻职责。
- 状态枚举：
  - `PASS`：规则与当前源码一致，且有可定位证据。
  - `PARTIAL`：源码可证，但测试/流程证据未形成闭环。
  - `GAP`：流程层已明确记录缺口。
  - `MISMATCH`：当前规则文档与实现不一致。
- 置信度：
  - `High`：源码直接可证。
  - `Medium`：依赖推断或缺少执行证据。
  - `Low`：存在冲突或关键证据缺失。

## 2. 追溯矩阵

| Rule ID | Current Rule Doc | Expected Surface | Expected Test / Evidence | Current Evidence | Status |
| --- | --- | --- | --- | --- | --- |
| AC-01 | `docs/spec/access-control.md`（`uAsset` 权限边界） | owner 设置 / 撤销 minter cap；minter 可在额度内 mint | `test/assets/OutrunUniversalAssets.t.sol` | `src/assets/base/OutrunUniversalAssets.sol:checkMintableAmount/mint/repay/setMintingCap/revokeMinter` | PASS / High |
| AC-02 | `docs/spec/access-control.md`（`position` 权限边界） | owner 可 pause / unpause / 配 keeper / revenuePool / minStake；position owner 可 draw / redeem；keeper 可 keepRedeem | `test/position/OutrunStakingPosition.t.sol` | `src/position/OutrunStakingPosition.sol:pause/unpause/setKeeper/setRevenuePool/setMinStake/drawUAsset/redeem/keepRedeem/harvestWrapYield` | PASS / High |
| AC-03 | `docs/spec/access-control.md`（`router` 权限边界） | owner 可 setMemeverseLauncher；其余入口 permissionless | `test/router/OutrunRouter.t.sol` | `src/router/OutrunRouter.sol:setMemeverseLauncher + 全部公开路由入口` | PASS / High |
| AC-04 | `docs/spec/access-control.md`（`SY` / pausable 权限边界） | SY owner 可 pause / unpause；deposit / redeem 受 whenNotPaused 保护 | `test/yield/SYBaseDeposit.t.sol` | `src/yield/SYBase.sol:deposit/redeem` 均带 `whenNotPaused` | PASS / High |
| ACC-01 | `docs/spec/accounting.md`（uAsset minter-cap 账务） | mint 冲减 minter 额度；repay 冲减 minter 的 amountInMinted；revokeMinter 只设 cap=0 | `test/assets/OutrunUniversalAssets.t.sol` | `src/assets/base/OutrunUniversalAssets.sol` mint/repay/setMintingCap/revokeMinter 代码路径 | PASS / High |
| ACC-02 | `docs/spec/accounting.md`（Position debt 账务） | stake 时按 exchangeRate 折算 principalValue 写入初始 UAssetMinted | `test/position/OutrunStakingPosition.t.sol` | `src/position/OutrunStakingPosition.sol:stake()` 使用 `SYUtils.syToAsset(exchangeRate, amountInSY)` 计算 principalValue | PASS / High |
| ACC-03 | `docs/spec/accounting.md`（Wrap 池账务） | wrapStake 增加 syTotalStaking/syWrapStaking/wrapUAssetDebt；wrapRedeem 同步减少 | `test/position/OutrunStakingPosition.t.sol` | `src/position/OutrunStakingPosition.sol:wrapStake/wrapRedeem` 三条账务变量同步更新 | PASS / High |
| ACC-04 | `docs/spec/accounting.md`（按比例销债） | redeem 时 `UAssetBurned = UAssetMinted * syRedeemed / syStaked` | `test/position/OutrunStakingPosition.t.sol` | `src/position/OutrunStakingPosition.sol:redeem()` 中的比例计算与 `_applyPositionRedeem` | PASS / High |
| ACC-05 | `docs/spec/accounting.md`（Keeper redeem 分账） | keeper 烧 uAsset 换 keeperPrincipalSY；owner 收剩余 excess SY | `test/position/OutrunStakingPosition.t.sol` | `src/position/OutrunStakingPosition.sol:keepRedeem()` 的分账路径 | PASS / High |
| ACC-06 | `docs/spec/accounting.md`（Harvest 账务） | harvestAmount = syWrapStaking - assetToSy(wrapUAssetDebt)；减少 pool 账务，不改变用户 debt | `test/position/OutrunStakingPosition.t.sol` | `src/position/OutrunStakingPosition.sol:harvestWrapYield()` | PASS / High |
| SM-01 | `docs/spec/state-machines.md`（Direct stake 生命周期） | stake -> 已创建、未到期、可 draw、不可 redeem | `test/position/OutrunStakingPosition.t.sol` | `src/position/OutrunStakingPosition.sol:stake()` 写入 position 与 deadline | PASS / High |
| SM-02 | `docs/spec/state-machines.md`（Draw 生命周期） | drawUAsset 只追加 debt，不改变 deadline 与 syStaked | `test/position/OutrunStakingPosition.t.sol` | `src/position/OutrunStakingPosition.sol:drawUAsset()` | PASS / High |
| SM-03 | `docs/spec/state-machines.md`（Redeem 生命周期） | 到期后 owner 可按比例赎回，部分赎回后 position 仍存在或清空删除 | `test/position/OutrunStakingPosition.t.sol` | `src/position/OutrunStakingPosition.sol:redeem()` + `remainingSY == 0` 删除逻辑 | PASS / High |
| SM-04 | `docs/spec/state-machines.md`（Wrap stake / wrap redeem 生命周期） | wrap stake 无 positionId，共享池账务；wrap redeem 按 exchangeRate 换算 SY | `test/position/OutrunStakingPosition.t.sol` | `src/position/OutrunStakingPosition.sol:wrapStake/wrapRedeem` | PASS / High |
| SM-05 | `docs/spec/state-machines.md`（Keeper redeem 生命周期） | keeper 代偿到期仓位，keeper 收 principal，owner 收 excess | `test/position/OutrunStakingPosition.t.sol` | `src/position/OutrunStakingPosition.sol:keepRedeem()` 分账代码 | PASS / High |
| SM-06 | `docs/spec/state-machines.md`（Pause / unpause 影响） | owner pause 阻断所有 whenNotPaused 入口；view / preview 不受影响 | `test/position/OutrunStakingPosition.t.sol` | `src/position/OutrunStakingPosition.sol` pause 修饰符覆盖的 7 个入口 | PASS / High |
| RF-01 | `docs/spec/router-and-user-flows.md`（Token/Native -> SY） | router caller-funded pull → SY.deposit → mint to receiver | `test/router/OutrunRouter.t.sol` | `src/router/OutrunRouter.sol:mintSYFromToken/_mintSY` | PASS / High |
| RF-02 | `docs/spec/router-and-user-flows.md`（Token/SY -> Locked Stake） | stakeFromToken 先 _mintSY 到 router，再 position.stake → uAsset mint to uAssetReceiver | `test/router/OutrunRouter.t.sol` | `src/router/OutrunRouter.sol:stakeFromToken/_stakeFromSYBalance`，`StakeParam.receiver` 分离 | PASS / High |
| RF-03 | `docs/spec/router-and-user-flows.md`（Wrap Redeem） | router 代收 uAsset → position.wrapRedeem → 输出 SY 或 target token | `test/router/OutrunRouter.t.sol` | `src/router/OutrunRouter.sol:wrapRedeem` | PASS / High |
| RF-04 | `docs/spec/router-and-user-flows.md`（Genesis） | genesis 走 locked stake，不是 wrap stake；uAsset 最终交 launcher | `test/router/OutrunRouter.t.sol` | `src/router/OutrunRouter.sol:genesisByToken/genesisBySY` | PASS / High |
| RF-05 | `docs/spec/router-and-user-flows.md`（Preview 语义边界） | preview 只做静态组合，不反映 minUAssetMinted / owner / receiver 差异 | `test/router/OutrunRouter.t.sol` | `src/router/OutrunRouter.sol:preview*` 四个入口均只做下游转发 | PASS / High |
| YA-01 | `docs/spec/yield-adapters.md`（SYBase 统一行为） | deposit/redeem 带 nonReentrant + whenNotPaused；ERC20 入金禁止 msg.value | `test/yield/SYBaseDeposit.t.sol` | `src/yield/SYBase.sol:deposit/redeem` | PASS / High |
| YA-02 | `docs/spec/yield-adapters.md`（Aave adapter） | underlying → supply → aToken；exchangeRate 用 normalizedIncome / 1e9 | PARTIAL: 仅 `previewRedeem(aToken)` 有直接覆盖 | `src/yield/adapters/aave/OutrunAaveV3SY.sol` | PASS / Medium |
| YA-03 | `docs/spec/yield-adapters.md`（Ether.fi adapter） | native → depositETHForWeETH；EETH → wrap；exchangeRate 用 amountForShare | PARTIAL: 仅 `deposit(EETH)` 有直接覆盖 | `src/yield/adapters/etherfi/OutrunWeETHSY.sol` | PASS / Medium |
| YA-04 | `docs/spec/yield-adapters.md`（Lido L1 adapter） | native → submit(address(0)) → wrap; exchangeRate 用 stEthPerToken | PARTIAL: 仅 `native deposit` 有直接覆盖 | `src/yield/adapters/lido/OutrunWstETHSY.sol` | PASS / Medium |
| YA-05 | `docs/spec/yield-adapters.md`（Lido L2 wrappable） | STETH ↔ wstETH wrap/unwrap; exchangeRate 走 oracle | `test/yield/OutrunL2WrappableWstETHSY.t.sol` | `src/yield/adapters/lido/OutrunL2WrappableWstETHSY.sol` | PASS / High |
| YA-06 | `docs/spec/yield-adapters.md`（Sky L1 adapter） | USDS → ERC4626 deposit(sUSDS); redeem → ERC4626 redeem | GAP: 无独立测试文件 | `src/yield/adapters/sky/OutrunStakedUsdsSY.sol` | PASS / Medium |
| YA-07 | `docs/spec/yield-adapters.md`（Ethena adapter） | USDE → ERC4626 deposit(sUSDe); redeem 只输出 sUSDe | GAP: 无独立测试文件 | `src/yield/adapters/ethena/OutrunStakedUSDeSY.sol` | PASS / Medium |
| OA-01 | `docs/spec/oracles-and-integrations.md`（Oracle adapter） | 读取 latestAnswer → 拒绝 ≤0 → 精度归一化 | `test/support/MockOracleWarnings.t.sol` | `src/libraries/oracle/OutrunExchangeOracleAdapter.sol` | PASS / High |
| OFT-01 | `docs/spec/common-foundations.md`（OFT 本地语义） | _debit burn / _credit mint; _toSD 溢出保护; 零地址改 0xdead | `test/assets/OutrunUniversalAssets.t.sol` | `src/assets/omnichain/OutrunOFT.sol` | PASS / High |
| CF-01 | `docs/spec/common-foundations.md`（TokenHelper） | NATIVE = address(0); _transferIn 校验 msg.value; _transferOut 统一发送 | `test/yield/SYBaseDeposit.t.sol` | `src/libraries/TokenHelper.sol:_transferIn/_transferOut` | PASS / High |
| CF-02 | `docs/spec/common-foundations.md`（ReentrancyGuard） | transient locked 防重入 | `test/yield/SYBaseDeposit.t.sol` 回调重入测试 | `src/libraries/ReentrancyGuard.sol` | PASS / High |
| CF-03 | `docs/spec/common-foundations.md`（SYUtils） | 1e18 基准的 syToAsset / assetToSy 双向换算 | 间接通过 position test 验证 | `src/libraries/SYUtils.sol` | PARTIAL / Medium |
| DEPL-01 | `docs/spec/deployment.md`（OutstakeScript run） | 默认只执行 _chainsInit + _deployOutrunRouter(7) | 脚本可追溯 | `script/deploy/OutstakeScript.s.sol:run()` | PASS / High |
| DEPL-02 | `docs/spec/deployment.md`（YieldDeployScript run） | 默认只执行 _supportAUSDC | 脚本可追溯 | `script/deploy/YieldDeployScript.s.sol:run()` | PASS / High |
| DEPL-03 | `docs/spec/deployment.md`（CREATE2+CREATE3 两段式部署） | Create2 部署 OutrunDeployer → CREATE3 部署合约 | 脚本可追溯 | `script/deploy/deployment/OutrunDeployer.sol` salt 用 `keccak256(abi.encodePacked(msg.sender, salt))` | PASS / High |
| TEST-01 | `docs/spec/testing-and-evidence.md`（测试覆盖缺口） | Sky/Ethena/generic L2 adapter 缺少独立测试 | 目录缺失可证 | `test/yield/` 下未见同名 adapter 测试文件 | GAP / High |
| TEST-02 | `docs/spec/testing-and-evidence.md`（Oracle 覆盖缺口） | 仅非正值拒绝 + L2 wrappable 有覆盖；无所有 L2 adapter 的统一 oracle 集成验证 | 目录缺失可证 | `test/support/MockOracleWarnings.t.sol` 只覆盖非正值 | PARTIAL / Medium |

## 3. 明确未知项

- 未提供生产部署清单，无法在本仓库内确认每条链上的最终 owner / keeper / revenuePool / launcher 地址。
- uAsset / SY / Position 是否已在某条链上完成实际部署，不属于本仓库可直接证明的事实。
- 跨链 OFT 的远端 peer 地址是否配置正确、LayerZero 端点消息是否送达，属于外部依赖边界。
