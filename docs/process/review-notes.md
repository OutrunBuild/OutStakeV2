# Review Note 规范

`docs/reviews/*.md` 默认是本地 review 草稿目录。命中 `src/**/*.sol`、`script/**/*.sol` 时，本地与 CI 的 `quality:gate` 都要求至少有一份有效 review note，作为安全、简化、Gas 与验证证据。

前置说明：

- 当前仓库已经落盘 `script/process/check-review-note.sh`、`script/process/check-solidity-review-note.sh`、`quality:quick` 与 `quality:gate`，本文件描述的约束会被这些 execution-plane 脚本直接消费。
- review note 校验仍只负责流程证据链；若仓库存在与当前流程任务无关的产品在制改动，`verifier` 需要把 repo-wide gate / compile 失败据实归因，不能把局部流程通过表述成全仓通过。

## 1. 语言与格式

- review note 正文默认使用简体中文。
- 固定 section / field key 保持英文。
- 路径、命令、代码标识、selector 保持英文原文。
- `Writer dispatch confirmed`、`Evidence chain complete`、`Behavior change`、`ABI change`、`Storage layout change`、`Config change`、`Ready to commit` 的值只能填写 `yes` 或 `no`。
- 所有 `* evidence source` 字段都采用 `role: source` 格式。

## 2. 必填章节

- `## Scope`
- `## Impact`
- `## Findings`
- `## Simplification`
- `## Gas`
- `## Docs`
- `## Tests`
- `## Verification`
- `## Decision`

## 3. 通用必填字段

以下字段是跨仓库共享的 Harness 基线：

- `Change summary`
- `Files reviewed`
- `Task Brief path`
- `Agent Report path`
- `Implementation owner`
- `Writer dispatch confirmed`
- `Semantic dimensions reviewed`
- `Source-of-truth docs checked`
- `External facts checked`
- `Local control-flow facts checked`
- `Evidence chain complete`
- `Semantic alignment summary`
- `Behavior change`
- `ABI change`
- `Storage layout change`
- `Config change`
- `Logic review summary`
- `Logic residual risks`
- `Security review summary`
- `Security residual risks`
- `Gas-sensitive paths reviewed`
- `Gas changes applied`
- `Gas snapshot/result`
- `Gas residual risks`
- `Docs updated`
- `Tests updated`
- `Existing tests exercised`
- `Commands run`
- `Results`
- `Codex review summary`
- `Logic evidence source`
- `Security evidence source`
- `Gas evidence source`
- `Codex review evidence source`
- `Verification evidence source`
- `Decision evidence source`
- `Ready to commit`
- `Residual risks`

## 4. Repo-specific 扩展字段

如果 `docs/process/policy.json`、`docs/process/rule-map.json` 或相关 gate 脚本要求额外字段，也必须填写。常见扩展示例：

- `Open safety mismatches assessed`
- `Rule-map evidence source`
- 其他仅在当前仓库策略文件中声明的字段

判断原则：

- 以 `docs/process/policy.json` 的 `review_note.*` 与 `solidity_review_note.*` 为准。
- 若仓库启用了 repo-specific 证据映射，review note 必须与其约束保持一致。

## 5. 字段职责

- `Task Brief path`、`Agent Report path`、`Implementation owner`、`Writer dispatch confirmed`
  - 默认由 `main-orchestrator` 汇总填写，用于证明该 Solidity 变更先有 brief，且 writer role 已按仓库契约派发并产出对应实现工件。
  - `Task Brief path` 默认应位于 `docs/task-briefs/`。
  - `Agent Report path` 默认应位于 `docs/agent-reports/`。
- 若 review note 用于流程面 evidence aggregation，仍应回溯到对应 `Task Brief path`、`Agent Report path` 与 verifier 结论；不得用聊天记录替代工件链。
- `Change summary`、`Files reviewed`、`Behavior change`、`ABI change`、`Storage layout change`、`Config change`
  - 默认由实现型 writer 提供：`solidity-implementer` 负责 Solidity 面，`process-implementer` 负责非 Solidity 面。
- `Semantic dimensions reviewed`、`Source-of-truth docs checked`、`External facts checked`、`Semantic alignment summary`
  - 默认由 `main-orchestrator` 汇总 brief、review 结论与外部证据后填写。
- `Local control-flow facts checked`、`Evidence chain complete`
  - 默认由 `main-orchestrator` 在复核关键代码行、关键前提与必要外部主来源后填写。
- `Logic review summary`、`Logic residual risks`、`Logic evidence source`
  - 默认由 `logic-reviewer` 提供。
- `Security review summary`、`Security residual risks`、`Security evidence source`
  - 默认由 `security-reviewer` 提供。
- `Gas-sensitive paths reviewed`、`Gas changes applied`、`Gas snapshot/result`、`Gas residual risks`、`Gas evidence source`
  - 默认由 `gas-reviewer` 提供。
- `Docs updated`
  - 默认由 `solidity-implementer` 或 `process-implementer` 提供。
- `Tests updated`、`Existing tests exercised`
  - 默认由 `solidity-implementer` 或 `security-test-writer` 提供；非 Solidity 流程任务中也可由 `process-implementer` 汇报。
- `Commands run`、`Results`、`Verification evidence source`
  - 默认由 `verifier` 提供。
  - `verifier` 仍负责 `Commands run`、`Results` 中的验证 verdict，以及相关证据链；writer 侧字段轻量化不会减轻 `verifier` 的证据责任。
  - `Results` 必须包含 required commands 的通过/失败结论与 failure attribution，不能只写“已跑 gate”。
- `Codex review summary`、`Codex review evidence source`
  - 默认由 `verifier` 提供，用于记录 writer 完成后的一次独立 Codex 审查与 findings 收口。
- `Ready to commit`、`Decision evidence source`
  - 只能由 `main-orchestrator` 最终判定。

## 6. 防误报与证据链规则

证据链、hard-block 与 soft-block 的完整定义见 `AGENTS.md §10`。

- `Local control-flow facts checked` 必须写清结论依赖的本地关键前提，例如状态更新顺序、条件分支、金额处理、索引推进、返回值处理或权限检查。
- 若结论依赖第三方协议、外部合约、SDK、API 或系统行为，`External facts checked` 必须写明主来源；没有主来源时只能写成 `needs verification`、假设或待确认决策点。
- `Evidence chain complete` 只有在“本地前提已复核”且“必要时外部主来源已核验”同时满足时才允许填写 `yes`。
- 若某条结论只来自 subagent 摘要而主会话未复核关键代码行，该条结论不得在 review note 中写成已确认 finding。
- 对 `prod-semantic` / `high-risk` 的 `src/**/*.sol`、`script/**/*.sol` 写面，本地 `quality:gate`（含 `pre-commit`）会在进入 review-note / verifier 校验前自动再执行一次 `npm run codex:review`；`pre-push` / CI 只校验证据链，不自动执行。`non-semantic` / `test-semantic` 与流程面默认按需手动触发。若当前交互会话支持 `/review`，可视为同义入口，但落盘 evidence 仍以 wrapper / CLI 命令为准。
- 对 `src/**/*.sol`、`script/**/*.sol` 写面，`Logic evidence source`、`Security evidence source`、`Gas evidence source`、`Verification evidence source` 必须指向可落盘、可回溯的具体 artifact path；不能只写命令名、聊天结论或模糊描述。
- 如果 `solidity-implementer` 在 review finding 之后再次写入受影响的 Solidity scope，上一轮 review note 与上述 reviewer / verifier evidence 都会被视为 stale；它们必须在最新 writer `Agent Report` 之后重新生成。
- `Codex review evidence source` 可以继续记录 wrapper / CLI 命令，但承载该字段的 review note 必须晚于当前 writer `Agent Report`。
- 当某个 reviewer 没有被 classifier 选中时，对应 review-note 字段应保留 owner-prefixed 说明，例如 `security-reviewer: skipped by classifier (non-semantic)`；不得伪造不存在的 reviewer artifact path。
- stale-evidence freshness 只针对当前 classifier 选中的 reviewer / verifier evidence；未被 classifier 选中的 reviewer 字段不作为 freshness blocker。
- 发现 stale evidence 后，`quality:gate` 会默认触发 `npm run stale-evidence:loop`；它会生成新的 follow-up brief，并给出 writer / reviewer / verifier 的 rerun order。
- 当路径命中 `src/assets/**`、`src/position/**`、`src/yield/**`、`src/router/**`、`src/integrations/**` 或 `src/libraries/**`（含 `src/libraries/IWETH.sol`）的语义敏感表面时，review note 还应显式交代 reward/accounting、router settlement、oracle assumption、position lifecycle 或外部依赖语义中哪几项被审阅过。
- 当 `Task Brief` 已声明 `Semantic review dimensions`、`Source-of-truth docs`、`External sources required` 时，`check-solidity-review-note.sh` 会把这些声明与 review note 对应字段做对齐校验；语义敏感表面不允许把这些字段写成 `none`，且 `Evidence chain complete` 必须为 `yes`。
- 当 `Task Brief` 声明了 `Critical assumptions to prove or reject` 时，machine policy 会要求配置指定的 review-note 字段同步反映这些假设；当前仓库复用 `Semantic alignment summary` 作为该对齐字段。
- 对任意 `src/**/*.sol` 或 `script/**/*.sol` 变更，只要 `Task Brief` 显式声明了这些字段，semantic-alignment gate 都会被收紧；`semantic_sensitive_patterns` 只在没有显式 brief 声明时提供额外兜底。

## 7. 禁止内容

以下内容会被脚本视为无效或高风险信号：

- 空字段
- `TBD`
- `<path>`
- `<path>|none`
- `<selectors or paths>`
- `yes/no`
- 其他仍保留在模板状态、不能形成证据的占位值

## 8. 使用方式

- 需要本地记录审阅结论时，可基于 `docs/reviews/TEMPLATE.md` 新建草稿。
- 命中 `src/**/*.sol`、`script/**/*.sol` 变更且准备运行本地或 CI `quality:gate` 时，必须先准备好一份可通过校验的 review note。
- 仅检查草稿结构可运行：`bash ./script/process/check-review-note.sh <review-note>`
- 需要在 Solidity gate 中联动检查时，可运行：`bash ./script/process/check-solidity-review-note.sh`
- 若未显式设置 `QUALITY_GATE_REVIEW_NOTE`，Solidity gate 只会自动选择一份 `Files reviewed` 能唯一匹配当前变更 Solidity 路径的 review note；若存在歧义或没有匹配，必须显式指定。
- 若仓库跟踪了特定 review note 文件，它也必须与当前改动、当前 gate 语义保持一致。
