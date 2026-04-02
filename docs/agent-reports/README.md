# Agent Reports

本目录存放 OutStakeV2 本地 `Agent Report` 工件。

- `Agent Report` 是 subagent / reviewer / verifier 的结构化执行或审阅证据
- `Agent Report` 不属于设计文档、实现计划或拆分草案，因此不应放入 `docs/plans/`
- `Task Brief`、design、implementation plan 仍按仓库约定保存在各自目录
- 按 `.codex/templates/agent-report.md`，核心 6 个 `required` fields 是 `Role`、`Summary`、`Task Brief path`、`Scope / ownership respected`、`Files touched/reviewed`、`Residual risks`
- 按 `.codex/templates/agent-report.md`，核心 4 个 `conditional` fields 是 `Findings`、`Required follow-up`、`Commands run`、`Evidence`
- `conditional` 字段可以省略，但如果某个角色的结论依赖它，就必须填写

命名建议：

- `<date>-<topic>-<role>-report.md`

示例：

- `2026-03-27-comment-quality-implementer-report.md`
- `2026-03-27-comment-quality-security-report.md`
- `2026-03-27-comment-quality-gas-report.md`
