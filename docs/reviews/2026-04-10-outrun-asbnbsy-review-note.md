# Review Note

## Scope
- Change summary: 新增 `OutrunAsBNBSY`，接入 Aster `asBNB`，支持 `BNB / slisBNB / asBNB` 同步入金，仅支持 `asBNB` 赎回；新增 Aster 最小接口、unit/fuzz/fork 测试；后续修复了 native canonical asset 下的 `exchangeRate` 计价闭环、constructor fail-fast 顺序，以及 `zero-shares` 与 `queued mint` 错误语义分流。
- Files reviewed: src/integrations/aster/interfaces/IAsBnbMinter.sol; src/integrations/aster/interfaces/IYieldProxy.sol; src/integrations/aster/interfaces/IListaBNBStakeManager.sol; src/yield/adapters/aster/OutrunAsBNBSY.sol; test/yield/mocks/AsterSYMocks.sol; test/yield/OutrunAsBNBSY.t.sol; test/yield/OutrunAsBNBSYFuzz.t.sol; test/yield/OutrunAsBNBSYFork.t.sol
- Task Brief path: docs/task-briefs/2026-04-10-outrun-asbnbsy-task-brief.md
- Agent Report path: docs/agent-reports/2026-04-10-outrun-asbnbsy-solidity-implementer-report.md
- Implementation owner: solidity-implementer
- Writer dispatch confirmed: yes
- Semantic dimensions reviewed: Aster queue 语义与同步 `deposit()` 对齐；native canonical asset 下 `exchangeRate/previewDeposit` 计价闭环；constructor fail-fast 顺序；外部 live wiring / quote；queue/zero-shares 错误语义分流
- Source-of-truth docs checked: `AGENTS.md`; `docs/process/change-matrix.md`; `docs/process/review-notes.md`; `docs/process/policy.json`; `docs/superpowers/specs/2026-04-10-outrun-asbnbsy-design.md`; `docs/superpowers/plans/2026-04-10-outrun-asbnbsy.md`; `src/yield/SYBase.sol`; `src/yield/interfaces/IStandardizedYield.sol`; `src/libraries/TokenHelper.sol`; `src/libraries/SYUtils.sol`; `src/position/OutrunStakingPosition.sol`
- External facts checked: main-orchestrator: Aster docs `https://docs.asterdex.com/earn/overview/mint-asbnb` 与 `https://docs.asterdex.com/overview/smart-contracts`; BscScan 已验证 `AsBnbMinter` 实现 `https://bscscan.com/address/0x7f52773065fd350b5a935ce2b293fdb16551a6fc#code`; `YieldProxy` 实现 `https://bscscan.com/address/0x1b04834f51574ffdef7511e271c09d4070de1b1a#code`; Lista stake manager 暴露 `convertBnbToSnBnb/convertSnBnbToBnb` 的已验证实现 `https://bscscan.com/address/0x89b2eb59c6b77c244407defa926a97c01fe9486a#code`
- Local control-flow facts checked: main-orchestrator: `SYBase.deposit()` 先 `_transferIn` 再 `_deposit`；`OutrunAsBNBSY._deposit()` 在 `mintAsBnb*()` 返回 `0` 时调用 `_revertOnZeroShares()`，按 `YIELD_PROXY.activitiesOnGoing()` 区分 `AsBnbMintQueued` 与 `AsBnbMintZeroShares`，所有路径都发生在 `_mint(receiver, amountSharesOut)` 之前；`exchangeRate()` 现在先 `convertToTokens(1e18)` 再 `convertSnBnbToBnb(...)`，与 `assetInfo() = (TOKEN, NATIVE, 18)` 落在同一 asset domain
- Evidence chain complete: yes
- Semantic alignment summary: 本地控制流、reviewer 结论、主网 fork 和上游主来源已经闭合：`deposit(BNB/slisBNB)` 的 queued path 会整笔回滚，无 half-state；constructor zero-check 已前移到 `SYBase(...)` 参数求值前；native canonical asset 下 `exchangeRate()` 改成 BNB 计价后，已修复把 `slisBNB` quote 当作 `BNB` asset 的账务错配。剩余 only residual risk 是 live `previewDeposit(BNB)` 与 `SYUtils.assetToSy(exchangeRate, amount)` 在真实两跳取整下存在 bounded wei rounding drift，而不是方向性错配。

## Impact
- Behavior change: yes
- ABI change: yes
- Storage layout change: no
- Config change: yes

## Findings
- High findings: none
- Medium findings: none
- Low findings: live `previewDeposit(BNB)` 与 `SYUtils.assetToSy(exchangeRate, amount)` 在主网真实两跳取整下存在 bounded wei rounding drift；fresh `CODEX_REVIEW_BACKEND=claude npm run codex:review` 仍提示 NatSpec gaps 与 test fragility，归类 non-blocking low items
- None: none
- Logic review summary: logic-reviewer: 无 confirmed blocker；native-denominated `exchangeRate`、`AsBnbMintZeroShares/AsBnbMintQueued` 分流、constructor fail-fast 顺序和 unit/fuzz/fork 覆盖都已对齐当前设计
- Logic residual risks: logic-reviewer: 主网 live `exchangeRate` 与 `previewDeposit(BNB)` 不保证 exact 相等，只支持 bounded rounding drift；fork 仍是只读验证，不证明 active queue 窗口下可重复触发
- Logic evidence source: logic-reviewer: docs/agent-reports/2026-04-10-outrun-asbnbsy-logic-reviewer-report.md
- Security review summary: security-reviewer: NO_FINDINGS；queue revert 半状态、constructor 接线校验、`redeem(asBNB)` 资金面和失败路径测试覆盖均成立
- Security residual risks: security-reviewer: 依赖外部 UUPS proxy 语义与无限授权；未做“上游返回非零但少 mint / 错 mint receiver”的对抗性测试
- Security evidence source: security-reviewer: docs/agent-reports/2026-04-10-outrun-asbnbsy-security-reviewer-report.md

## Simplification
- Simplification: 保持最小接口面；保持 `_safeApproveInf` 与现有 SY adapter 风格一致；保持 only-`asBNB` redeem，不引入异步退出状态机
- Follow-up simplifications: 若后续确认 `previewDeposit(BNB)` 的 live rounding drift 需要统一容差语义，可单独补 fork invariant / docs，不建议在当前变更内继续扩大实现面

## Gas
- Gas-sensitive paths reviewed: `deposit(slisBNB)` 授权热路径；`exchangeRate()` 两跳静态 quote；`previewDeposit(NATIVE)` 使用 immutable `STAKE_MANAGER`
- Gas changes applied: native canonical asset 修复后，`exchangeRate()` 新增 `convertSnBnbToBnb` staticcall；`AS_BNB_MINTER/YIELD_PROXY/STAKE_MANAGER` immutable 缓存已落地
- Gas snapshot/result: gas-reviewer: 无需立即修复的 gas finding；`activitiesOnGoing()` 判别只在 0-share 回退路径触发；`deposit(slisBNB)` 首笔授权初始化、后续复用 allowance
- Gas residual risks: 高频 `deposit(slisBNB)` 场景下 allowance probe 会累计成本；`exchangeRate()` 与 error classification 依赖额外外部只读调用
- Gas evidence source: gas-reviewer: docs/agent-reports/2026-04-10-outrun-asbnbsy-gas-reviewer-report.md

## Docs
- Docs updated: yes; 新增/更新 `docs/task-briefs/2026-04-10-outrun-asbnbsy-task-brief.md`、4 份 reviewer/implementer report、1 份 verifier report、本 review note
- No-doc reason: not applicable

## Tests
- Tests updated: yes; 新增 unit/fuzz/fork，覆盖 constructor fail-fast、token universe、queue vs zero-shares、native canonical asset 闭环、live wiring 与 live quote
- Existing tests exercised: `forge test -vvv --match-path test/yield/OutrunAsBNBSY.t.sol`; `forge test -vvv --match-path test/yield/OutrunAsBNBSYFuzz.t.sol`; `forge test -vvv --match-path test/yield/OutrunAsBNBSYFork.t.sol`
- No-test-change reason: not applicable

## Verification
- Commands run: `forge fmt --check src/integrations/aster/interfaces/IAsBnbMinter.sol src/integrations/aster/interfaces/IYieldProxy.sol src/integrations/aster/interfaces/IListaBNBStakeManager.sol src/yield/adapters/aster/OutrunAsBNBSY.sol test/yield/mocks/AsterSYMocks.sol test/yield/OutrunAsBNBSY.t.sol test/yield/OutrunAsBNBSYFuzz.t.sol test/yield/OutrunAsBNBSYFork.t.sol`; `forge build`; `forge test -vvv --match-path test/yield/OutrunAsBNBSY.t.sol`; `forge test -vvv --match-path test/yield/OutrunAsBNBSYFuzz.t.sol`; `forge test -vvv --match-path test/yield/OutrunAsBNBSYFork.t.sol`; `CODEX_REVIEW_BACKEND=claude npm run codex:review`
- Results: 当前 `fmt/build/unit/fuzz/fork/codex-review` 全部通过；其中 unit `32/32`、fuzz `4/4`、fork `3/3`。fresh `codex review` 无 `high` finding；唯一 `medium` 为已在代码中记录的外部 trust boundary 设计依赖，其余为非阻断 low item。`check-solidity-review-note.sh` 与 `quality:gate:fast` 尚未执行。
- Codex review summary: `CODEX_REVIEW_BACKEND=claude npm run codex:review` exit `0`；最新 review 结论为无 `high` finding，唯一 `medium` 项 `F-1` 是已在代码中记录的外部 trust boundary 设计决策，`low` 项为 NatSpec gaps 与测试脆弱性，均非阻断
- Codex review evidence source: verifier: docs/agent-reports/2026-04-10-outrun-asbnbsy-verifier-report.md
- Verification evidence source: verifier: docs/agent-reports/2026-04-10-outrun-asbnbsy-verifier-report.md

## Decision
- Ready to commit: no
- Residual risks: 仍未执行 `bash ./script/process/check-solidity-review-note.sh` 与 `npm run quality:gate:fast`；此外 live native canonical asset 闭环仅能保证 bounded rounding drift，不保证 exact zero-drift equality
- Decision evidence source: main-orchestrator: docs/agent-reports/2026-04-10-outrun-asbnbsy-verifier-report.md

## Repo-specific Extensions
- Open safety mismatches assessed: yes; queue revert、zero-shares 分流、native canonical asset 计价闭环、external trust boundary 与 live wiring 都已复核；剩余 mismatch 仅为 bounded rounding drift 和外部可升级依赖
- Rule-map evidence source: main-orchestrator: docs/task-briefs/2026-04-10-outrun-asbnbsy-task-brief.md
