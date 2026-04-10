---
paths:
  - "src/**/*.sol"
  - "test/**/*.sol"
  - "test/**/*.t.sol"
  - "script/**/*.sol"
  - "docs/spec/**"
  - "docs/superpowers/specs/**"
  - "docs/task-briefs/**"
  - "docs/agent-reports/**"
  - "docs/reviews/**"
---

# Workflow Precedence

## AGENTS.md 工作流优先于任何插件/skill 工作流

当 AGENTS.md 定义的工作流（Phase 1-10、Review Order、Evidence Chain）与任何插件或 skill 的工作流冲突时，**始终以 AGENTS.md 为准**。

### 具体规则

1. **不得用插件 skill 的 review 阶段替代 AGENTS.md 的 review order**
   - AGENTS.md §5 定义的 review order（non-semantic / test-semantic / prod-semantic）是唯一有效的审阅流程
   - 禁止用 superpowers code-reviewer、spec-reviewer 或其他插件 review 替代 AGENTS.md 中的 logic-reviewer / security-reviewer / gas-reviewer / verifier

2. **不得跳过证据链中的任何必需工件**
   - Solidity 变更必须有：Task Brief → Agent Report → codex review → review note → verifier evidence → quality:gate
   - Spec surface 变更必须有：Task Brief → Agent Report → spec-reviewer Agent Report → codex review → verifier evidence
   - 插件 skill 不得省略或替代这些工件

3. **classify:change 必须在 review 前执行**
   - 对 `src/**/*.sol` / `script/**/*.sol` 变更，必须先跑 `npm run classify:change` 确定 review 等级
   - 不能跳过分类直接进入实现或 review

4. **Phase 顺序不可打乱**
   - Phase 1-10 的准入/准出条件必须按序满足
   - 不能因为插件 skill 的便利性而跳过 phase

5. **插件 skill 只在 AGENTS.md 未约束的空白处生效**
   - 插件的 brainstorming、plan writing、test-driven-development 等 skill 可在 AGENTS.md 未约束的细节层面使用
   - 但这些 skill 的输出仍须满足 AGENTS.md 对工件的要求
