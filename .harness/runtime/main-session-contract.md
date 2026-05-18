# Main Session Contract

## Read Order

1. `AGENTS.md`
2. `.harness/policy.json`
3. this file
4. `docs/TRACEABILITY.md` when you need control-file or artifact locations
5. `docs/VERIFICATION.md` when you need verification profile or verdict rules
6. `script/harness/gate.sh` when you need enforcement details or emitted evidence

## Truth Precedence

1. explicit human instruction
2. `.harness/policy.json`
3. `script/harness/gate.sh` results
4. `AGENTS.md` and this file
5. other repository docs

## Main-Session Rules

- `main-orchestrator` stays in the primary session and is never a project agent file.
- Every repository modification must go through `gate.sh --classify-only` before editing.
- Dispatch and review are selected by policy-derived `orchestration_profile`.
- Main session may directly modify files only for `direct` and `direct-review`.
- Main session must not author `delegated`, `full-review`, or `full-subagent` changes except to integrate approved subagent output.
- Do not dispatch writer or reviewer agents for `direct`.
- Do not bypass `process-implementer`, `spec-reviewer`, or human confirmation for docs/spec or spec-readiness changes.
- Production Solidity semantic changes without structural escalation require a main-session Risk Analysis Record before using `direct-review`; otherwise use `full-review`.
- README.md editorial-only direct changes require a Doc Editorial Attestation; otherwise use `delegated`.
- `direct-review` reviewer roles come from `orchestration_review_roles`, not `full_review_matrix`.
- Dispatch consumes resolved `selected_writer_roles` and `selected_review_roles`.
- For local current work, invoke `gate.sh` with exact changed-file input. If any Solidity file is involved, provide diff evidence through `CHANGE_CLASSIFIER_DIFF_FILE` or `GATE_DIFF_BASE`.
- Completion claims require fresh output from the selected matching `gate.sh` profile.
