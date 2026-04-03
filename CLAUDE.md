# Agent Operating Contract

`OutStakeV2` 仓库主流程契约，定义角色职责、阶段流、路径触发规则、完成标准与标准化 Solidity 工作流入口。

## 1. Project Overview

以 Foundry 为主的 Solidity 仓库，聚焦 staking / yield / router / oracle / external integration 合约表面，核心包含：

- `src/assets/`：资产主模型、资产接口与 omnichain 资产表面
- `src/position/`：staking position 主逻辑、根目录主文件与 position interfaces
- `src/yield/`：根目录 `SYBase.sol`、yield interfaces 与 adapter 表面
- `src/router/`：根目录 `OutrunRouter.sol`、面向用户与集成方的路由入口与 router interfaces
- `src/integrations/`：外部协议 interface、adapter helper、oracle adapter 与 deployment surface
- `src/libraries/`：跨业务域共享的数组 / ID / 数学 / reentrancy / token helper 等底层能力
- `test/`：按 `assets / position / router / yield / support` 分域的 Foundry 测试
- `script/`：按 `deploy / lib / ops / process` 分层的 Foundry 脚本与流程入口；`script/process/` 为 execution-plane
- `docs/process/`：流程文档与机器真源
- `docs/superpowers/specs/`、`docs/superpowers/plans/`：本地设计文档、实现计划与迁移方案
- `docs/task-briefs/`：本地 `Task Brief` 工件
- `docs/agent-reports/`：本地 `Agent Report` 工件（独立 workflow artifact，不并入 `docs/plans/`；字段真源以 `.codex/templates/agent-report.md` 和 `docs/process/policy.json` 为准）
- `docs/reviews/`：本地 review 草稿模板与草稿
- `.claude/agents/`：subagent 定义（`.md`，含 YAML frontmatter）
- `.claude/rules/`：路径触发规则（`paths:` frontmatter）
- `.codex/templates/`：`Task Brief` 与 `Agent Report` 模板（保留兼容）

## 1.5 Subagent Runtime Entry

- 调度方式：Claude Code Agent tool + `.claude/agents/*.md`
- 角色运行时契约：`.claude/agents/*.md`（合并了原 `.codex/agents/*.toml` 元数据和 `*.md` 运行时契约）
- 参考索引：`.codex/workflows/solidity-subagent-workflow.json`、`.codex/runtime/subagent-runtime.json`
- `script/process/` 是 execution-plane 的验证与 gate 脚本，不是 subagent dispatch backend
- 机器规则真源：本文件、`docs/process/subagent-workflow.md`、`docs/process/policy.json`、`script/process/*`、`.claude/agents/*.md`

## 2. Required Commands

仓库是 Foundry-only；不得重新引入 Hardhat / TypeScript deployment 语义。

初次设置：`git submodule update --init --recursive` → `npm install` → `npm run hooks:install`

常用命令：`forge build` | `forge test -vvv` | `forge fmt --check` | `forge coverage --ir-minimum`

本地 gate：`npm run quality:quick`（快速反馈）| `npm run quality:gate`（唯一 finish gate）

其他：`npm run process:selftest` | `npm run codex:review`（手动高风险审查）| `npm run docs:check`

说明：
- `quality:quick` / `quality:gate` 命中 `script/process/**`、`docs/process/policy.json`、`package.json`、`package-lock.json` 或 `.codex/runtime/**` 时，会执行 `process:selftest`
- 命中 `script/process/**/*.js` 时，流程 gate 会执行 `node --check` 作为 JS 语法检查
- 当前仓库存在与本任务无关的在制改动时，`quality:gate` / 全量编译是否通过由 `verifier` 据实归因；局部流程迁移任务可以以 `docs:check`、`process:selftest` 与可归因的局部 gate 结果作为完成依据，但不得把未验证状态表述为通过

## 3. Role Model

### Main Session

- `main-orchestrator` 是默认主会话角色（Claude Code 主会话直接承担），负责 intake、拆任务、划定 file ownership、汇总证据、判定 block
- 不是 product / process / config surface 的默认写入者；除 orchestration artifact（如 `docs/task-briefs/*`）外，不直接改仓库文件
- 不写：`src/**/*.sol`、`script/**/*.sol`、`test/**/*.sol`、`script/**/*.sh`、`script/process/**`、`CLAUDE.md`、`docs/process/**`、`.claude/**`、`.codex/**`、`.github/**`、`.githooks/*`、`package.json`、`package-lock.json`
- 命中上述路径或其他流程面文件时，必须先派发对应 writer role；若派发失败，必须停止并请求人工决策，不能降级为直接实现者
- 自主委派仍必须遵守角色边界、单写 owner、证据链和 block 规则

### Default Roles

| 角色 | 权限 | 职责 | 启用条件 |
|---|---|---|---|
| `solidity-implementer` | 可写 | Solidity surface 唯一默认写入者，负责 `src/**/*.sol`、`script/**/*.sol`、方法内注释与风险匹配的测试 | 始终 |
| `process-implementer` | 可写 | 非 Solidity surface 默认写入者，负责流程、文档、CI、`script/process/**`、shell、`.githooks/*`、package metadata | 始终 |
| `logic-reviewer` | 只读 | 控制流、状态迁移、边界条件、语义偏差与可简化点 | `test-semantic`+ |
| `security-reviewer` | 只读 | findings、测试缺口与残余风险 | `prod-semantic`+ |
| `gas-reviewer` | 只读 | 热路径、Gas diff、优化建议与残余风险 | `prod-semantic`+ |
| `verifier` | 只读 | 验证执行与失败归因（`light` / `full` 两档） | 始终 |

### On-Demand Roles

- `solidity-explorer`：复杂改动前的影响面侦察与任务拆分建议
- `security-test-writer`：高风险改动后的 fuzz / invariant / adversarial tests 补强

### Required Review Order

**流程面变更**（`CLAUDE.md`、`docs/process/**`、`.codex/**`、`script/process/**`）：`process-implementer` → `codex review` → `verifier`

**Solidity 变更**（`src/**/*.sol` / `script/**/*.sol` / `test/**/*.sol`）：必须先运行 `npm run classify:change`，再按分类选择审阅流程：

- `non-semantic`：`solidity-implementer` → `codex review` → `verifier(light)`
- `test-semantic`：`solidity-implementer` → `logic-reviewer` → `codex review` → `verifier(light)`
- `prod-semantic`：`solidity-implementer` → `logic-reviewer` → `security-reviewer` → `gas-reviewer` → `codex review` → `verifier(full)`
- `high-risk`：同 `prod-semantic`，优先考虑 `security-test-writer` 补强测试

## 4. Core Principles

- **单写 owner**：同一批 Solidity 文件同一时间只能有一个实现型写入者；并行只用于只读任务
- **证据先于结论**：所有可提交结论必须能追溯到 `Task Brief`、agent 输出、review note、gate 或 CI；subagent finding 默认不是最终结论，`main-orchestrator` 必须复核关键代码行、前提和外部来源后才能升级
- **未完成证据链不得升级**：缺少本地关键前提、上游主来源或只依赖模式匹配 / mock / interface / wrapper 命名时，只能标记为 `hypothesis`、`needs verification` 或测试缺口
- **可读性优先于省注释**：非直观控制流、状态迁移、金额计算、权限前提与外部调用必须补充适量注释；禁止把显而易见的逐行语句翻译成噪音注释
- **测试充分性优先于"有测试就行"**：测试必须证明行为与风险边界，不能只停 happy path；涉及 reward/accounting、router settlement、position lifecycle、权限、资金流、oracle assumption 或外部集成的高风险路径，除单元测试外还必须补充 fuzz、invariant、adversarial、integration 或 upgrade tests，并明确覆盖范围与剩余缺口
- **本地前提先于外部事实**：结论必须先逐行核实本地关键控制流、状态更新与入口条件，再去核验第三方协议或外部系统行为
- **CI 不编排 agent**：CI 只验证证据与最终 gate
- **review 边界**：review 结论只允许输出风险、后果、证据与可选方案；不得擅自修改产品需求，不得把审阅建议固化为新规则；改变业务语义、权限边界、资金流约束、可领取条件、费用规则、兑换规则或其他产品规则的结论必须升级为 `需要 main-orchestrator / human 确认的决策点`

## 5. Workflow Summary

- `npm run quality:gate` 是唯一 finish gate；`npm run quality:quick` 只用于本地快速反馈
- 对 `src/**/*.sol` / `script/**/*.sol` / `test/**/*.sol` 变更，`Task Brief` 必须记录 `Change classification`、`Change classification rationale`、`Verifier profile`，并与 `npm run classify:change` 结果一致
- Artifact chain：
  - Solidity：`Task Brief → Agent Report → codex review → review note → verifier evidence → quality:gate → CI`
  - Process：`Task Brief → Agent Report → codex review → verifier evidence → docs:check / process:selftest`
- 工件目录：`docs/superpowers/specs/` 与 `docs/superpowers/plans/`（design/plan/draft）、`docs/task-briefs/`（Task Brief）、`docs/agent-reports/`（Agent Report）、`docs/reviews/`（review note/模板）
- 结构化阶段流、通信模型、证据链、block 规则以 `docs/process/subagent-workflow.md` 为准
- 新建文档前必须先校验目标目录是否符合仓库约定；路径未校验视为流程错误

## 6. Change Surfaces

- 路径触发规则、默认角色、必跑命令与 gate 约束以 `docs/process/change-matrix.md` 为准
- 机器可读真源以 `docs/process/policy.json`、`.codex/workflows/solidity-subagent-workflow.json`、`.codex/runtime/subagent-runtime.json`、`script/process/*` 为准

## 7. Pull Request Contract

模板：`.github/pull_request_template.md`，PR body 必须包含：`## Summary`、`## Impact`、`## Docs`、`## Tests`、`## Verification`、`## Risks`、`## Security`、`## Simplification`、`## Gas`

## 8. Review Note Contract

- 模板：`docs/reviews/TEMPLATE.md`
- 命中 `src/**/*.sol`、`script/**/*.sol` 变更时，本地与 CI 的 `quality:gate` 都必须能找到一份有效 review note
- 字段、布尔值约束、owner-prefixed source 规则以 `docs/process/review-notes.md` 和 `docs/process/policy.json` 为准

## 9. Local-Only Files

- `docs/superpowers/specs/`、`docs/superpowers/plans/`：仅放设计文档、实现计划、阶段方案、拆分草案
- `docs/task-briefs/`：仅放 `Task Brief`
- `docs/agent-reports/`：仅放 `Agent Report`
- `docs/reviews/`：review 草稿（是否提交由团队策略决定）

## 10. Documentation Language

新增自然语言文档默认简体中文；固定字段 key、命令、路径、代码标识、协议名、库名保持英文；review note 固定 key 与 `yes` / `no` 取值保持英文。

## 11. Repository Architecture Snapshot

| 层 | 目录 | 说明 |
|---|---|---|
| Asset | `src/assets/` | ERC20 / ERC6909 / omnichain principal-token 等资产主模型、接口与跨链资产能力 |
| Position | `src/position/` | staking position、`OutrunStakingPosition.sol`、position manager 交互、stake 状态与 position-oriented 入口 |
| Yield | `src/yield/` | `SYBase.sol`、yield interfaces 与 adapter 表面 |
| Router | `src/router/` | `OutrunRouter.sol`、聚合用户入口、协议内路由、组合调用与外部 launch/routing 适配 |
| Integration | `src/integrations/` | 第三方协议 interface、adapter helper、oracle adapter、deployment surface 与 upstream dependency 边界；结论依赖 `aave`、`etherfi`、`lido`、`lista`、`sky` 等上游行为时必须回到主来源核验 |
| Libraries | `src/libraries/` | 跨业务域共享的数组 / ID / 数学 / reentrancy / token helper 等底层能力 |
| Test | `test/` | 按 `assets / position / router / yield / support` 分域；通用 mock 与 support surface 进入 `test/support/` |
| Script | `script/` | `deploy/`（`.s.sol` 部署入口）、`lib/`（脚本基类）、`ops/`（shell 运维入口）、`process/`（execution-plane 稳定入口） |

## 12. Source of Truth And Reading Order

### Harness / Process Truth

`CLAUDE.md`（本文件）→ `docs/process/change-matrix.md` → `docs/process/review-notes.md` → `docs/process/policy.json` → `docs/process/rule-map.json`（若存在）→ `script/process/*` → `.claude/agents/*.md` → `.codex/agents/*.md`（历史参考）

### Product Truth

- Core：`README.md`、`foundry.toml`、`src/assets/**`、`src/position/**`、`src/yield/**`、`src/router/**`、`src/integrations/**`、`src/libraries/**`、`test/**`、`script/**`
- Support：`docs/superpowers/specs/*`、`docs/superpowers/plans/*`、`docs/reviews/TEMPLATE.md`、`docs/task-briefs/README.md`、`docs/agent-reports/README.md`

### Recommended Reading Order

1. `CLAUDE.md` → 2. `README.md` → 3. `foundry.toml` → 4. `src/assets/**`、`src/position/**`、`src/yield/**`、`src/router/**` → 5. `src/integrations/**`、`src/libraries/**` → 6. `test/**`、`script/**` → 7. `docs/process/subagent-workflow.md` + `docs/process/*`

## 13. Claude Code 适配说明

- 原 `.codex/agents/*.toml` + `*.md` 已合并至 `.claude/agents/*.md`；Claude Code 用 Agent tool 调度，不需 `.toml` manifest
- 路径触发规则已拆分至 `.claude/rules/*.md`（`paths:` frontmatter）
- `.codex/templates/`、`.codex/workflows/`、`.codex/runtime/` 保留为参考
- `main-orchestrator` 由主会话直接承担，不作为 subagent

| 角色 | Agent 文件 | 类型 |
|---|---|---|
| `solidity-implementer` | `.claude/agents/solidity-implementer.md` | 可写 |
| `process-implementer` | `.claude/agents/process-implementer.md` | 可写 |
| `logic-reviewer` | `.claude/agents/logic-reviewer.md` | 只读 |
| `security-reviewer` | `.claude/agents/security-reviewer.md` | 只读 |
| `gas-reviewer` | `.claude/agents/gas-reviewer.md` | 只读 |
| `verifier` | `.claude/agents/verifier.md` | 只读 |
| `solidity-explorer` | `.claude/agents/solidity-explorer.md` | 按需只读 |
| `security-test-writer` | `.claude/agents/security-test-writer.md` | 按需可写 |

Agent Report 输出契约不变（`.codex/templates/agent-report.md`）：
- Required：`Role`、`Summary`、`Task Brief path`、`Scope / ownership respected`、`Files touched/reviewed`
- Conditional：`Findings`、`Required follow-up`、`Commands run`、`Evidence`、`Residual risks`
