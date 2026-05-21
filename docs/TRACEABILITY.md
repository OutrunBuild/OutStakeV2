# OutStakeV2 Traceability

- Machine truth: .harness/policy.json
- Session contract: .harness/runtime/main-session-contract.md
- Policy schema: .harness/schemas/policy.schema.json
- Claude agents: .claude/agents/*
- Codex agents: .codex/agents/*
- Enforcement entrypoint: script/harness/gate.sh

For `prod-semantic` work, classification precedes dispatch. The main session decides whether spec/docs changes are needed before doc writers, `spec-reviewer`, code writers, or code reviewers are dispatched. Gate only classifies changed files and verification requirements.
