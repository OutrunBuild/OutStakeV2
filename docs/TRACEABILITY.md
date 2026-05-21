# OutStakeV2 Traceability

- Machine truth: .harness/policy.json
- Session contract: .harness/runtime/main-session-contract.md
- Policy schema: .harness/schemas/policy.schema.json
- Claude agents: .claude/agents/*
- Codex agents: .codex/agents/*
- Enforcement entrypoint: script/harness/gate.sh
- No-spec-change attestation input: `NO_SPEC_CHANGE_ATTESTATION_FILE`

For `prod-semantic` Solidity, the intended flow is two-step:

1. run the required spec/document workflow
2. classify code changes separately

For code-only classification, the `spec-readiness-doc-update` block may clear when either all mapped required docs are already present in the current diff scope or a valid no-spec-change attestation JSON is provided through `NO_SPEC_CHANGE_ATTESTATION_FILE`. The same exception also applies to mixed docs+code `prod-semantic` sets, but it clears only the residual `spec-readiness-doc-update` block. It does not bypass the two-step spec-readiness flow, lower mixed docs+code `prod-semantic` sets below the existing `full-review` minimum, or clear unrelated hard blocks.
