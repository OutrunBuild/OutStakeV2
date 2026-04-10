# Agent Detail Reference

本文件是 AGENTS.md §8 和 §9 的完整展开版，供 main-orchestrator 和按需加载使用。

---

## §A: Shared Agent Contract（完整版）

所有角色的通用输入、输出与决策规则。各角色 runtime contract 只需定义角色特有行为，不需要重复本节。

### 通用输入

- 结构化 Task Brief（分级模板见 `.codex/templates/task-brief.md`）
- 核心字段：`Goal`、`Files in scope`、`Write permissions`、`Implementation owner`、`Writer dispatch backend`、`Acceptance checks`、`Required verifier commands`
- 语义敏感改动需额外：`Semantic review dimensions`、`Source-of-truth docs`、`External sources required`、`Critical assumptions to prove or reject`

### 通用输出

标准化 Agent Report（模板见 `.codex/templates/agent-report.md`）：

- Required：`Role`、`Summary`、`Task Brief path`、`Scope / ownership respected`、`Files touched/reviewed`、`Residual risks`
- Conditional：`Findings`、`Required follow-up`、`Commands run`、`Evidence`
- spec surface reviewer artifact：spec review evidence，适用于 `docs/spec/**`、`docs/superpowers/specs/**`，以及当前 brief 声明为 spec 的产物；gate 会消费 brief 中的 `Artifact type: spec`、`Spec review required`、`Spec artifact paths`，并校验该证据 freshness / scope coverage。

### 通用决策规则

- 超出 brief scope 的写入 → hard-block，升级给 main-orchestrator
- 产品规则 / 业务语义可能被改变 → hard-block，升级为需要 human 确认的决策点
- reviewer / verifier finding 默认只是线索，main-orchestrator 必须复核关键代码行与前提后才能升级
- 回修轮次改用 Follow-up Brief（`.codex/templates/follow-up-brief.md`），明确 remediation scope、已失效 evidence 与 rerun order；spec surface 若 spec review evidence stale，会按当前 brief 声明的 spec scope 自动生成 Follow-up Brief。

## §B: Workflow Phases（完整版）

### Phase 1: Intake / Scoping

- `main-orchestrator` 创建 Task Brief（必须让未继承主会话历史的下游角色也能独立理解目标、边界与阻断条件）
- 对语义敏感改动，Task Brief 必须显式写出语义维度、真源文档、外部来源与关键假设
- 如影响面不清、跨模块，可按需启用 `solidity-explorer`
- 对 spec surface，Task Brief 必须明确 `Artifact type: spec`、`Spec review required: yes` 与 `Spec artifact paths`，但这些字段只表示契约标记，不替代路径触发。

### Phase 2: Baseline Analysis

- 运行 `npm run classify:change` 判定 `non-semantic` / `test-semantic` / `prod-semantic` / `high-risk`
- Task Brief 必须同步写出 Change classification、rationale 与 Verifier profile

### Phase 3: Implementation

- writer 在明确 ownership 下修改实现、补充注释与测试
- `main-orchestrator` 不得降级为直接实现者；派发失败只能停止并请求人工决策
- 不得未经派发扩大文件边界

### Phase 4: Spec Review（spec surface）

- `spec-reviewer` 对 spec surface 做只读审阅，覆盖事实、逻辑、范围与可执行性
- spec review evidence 是 spec surface 的约定 reviewer artifact
- 若 writer 再次改写同一 spec scope，上一轮 spec review evidence 在契约上视为 stale；自动 stale-remediation 会按 spec scope 重派 writer / spec-reviewer / verifier

### Phase 5: Codex Review（通用相位）

- spec surface 在 `spec-reviewer` 通过后进入后续动作
- 其他 surface 在各自前置 review 完成后，或无需额外 reviewer 时，进入各自后续动作

### Phase 6: Logic Review（`test-semantic`+）

- `logic-reviewer` 做只读逻辑审阅，覆盖控制流、状态迁移、边界条件
- 若 writer 再次改写同一 scope，上一轮证据自动失效，必须重跑

### Phase 7: Specialist Review（`prod-semantic`+）

- `security-reviewer` 与 `gas-reviewer` 输出只读结论
- review 必须先核本地前提（关键控制流、状态更新、金额处理、权限检查），再核验外部来源

### Phase 8: Test Hardening（`high-risk` 或 security-reviewer 指出缺口）

- `security-test-writer` 只修改测试，不修改生产逻辑

### Phase 9: Verification

- `verifier` 按 light / full 两档执行验证命令
- 必须独立检查 Task Brief、Agent Report、按 surface 对应的 reviewer artifact 与 failure attribution
- Solidity surface 的 reviewer artifact 是 `review note`
- spec surface 的 reviewer artifact 是 spec review evidence
- stale evidence（早于当前 writer Agent Report）必须阻断
- stale evidence 被 gate 检出时，自动生成 follow-up brief，`main-orchestrator` 按 rerun order 重新派发；这条自动 loop 同时覆盖 review-note / Solidity evidence 与 spec surface 的 stale spec review evidence

### Phase 10: Decision

- `main-orchestrator` 汇总全部证据，仅在证据链完整时允许进入 finish gate
- agent workflow 常用的本地默认收尾 gate 是 `npm run quality:gate:fast`
- 最终严格 finish gate 是 `npm run quality:gate`
- `npm run quality:gate:fast` / `npm run quality:gate` 命中特定路径时都会自动补跑 `npm run process:selftest`
