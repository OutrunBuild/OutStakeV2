# OutStakeV2 Traceability

- Machine truth: .harness/policy.json
- Session contract: .harness/runtime/main-session-contract.md
- Policy schema: .harness/schemas/policy.schema.json
- Claude agents: .claude/agents/*
- Codex agents: .codex/agents/*
- Enforcement entrypoint: script/harness/gate.sh

For `prod-semantic` Solidity, the intended flow is two-step:

1. run the required spec/document workflow
2. classify code changes separately

For code-only classification, the `spec-readiness-doc-update` block may clear when all mapped required docs are already present in the current diff scope. Mixed docs+code changed-file sets do not use this exception path.
