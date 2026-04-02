#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

tests=(
    "script/process/tests/codex-review.sh"
    "script/process/tests/logic-reviewer-contract.sh"
    "script/process/tests/brief-templates.sh"
    "script/process/tests/change-classifier.sh"
    "script/process/tests/stale-evidence-loop.sh"
    "script/process/tests/quality-gate-stale-remediation.sh"
    "script/process/tests/pre-push-quality-gate.sh"
    "script/process/tests/check-docs-agent-artifacts.sh"
    "script/process/tests/check-docs-task-brief-artifacts.sh"
    "script/process/tests/check-solidity-review-note.sh"
    "script/process/tests/quality-gates.sh"
    "script/process/tests/process-policy.sh"
)

for test_script in "${tests[@]}"; do
    echo "[process:selftest] bash ./$test_script"
    bash "./$test_script"
done

echo "[process:selftest] PASS"
