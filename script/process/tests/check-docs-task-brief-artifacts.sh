#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

tmp_dir="$(mktemp -d)"
plan_dir="$tmp_dir/plans"
tmp_brief="$plan_dir/zz-temp-task-brief-for-selftest.md"

cleanup() {
    rm -rf "$tmp_dir"
}
trap cleanup EXIT

mkdir -p "$plan_dir"

cat > "$tmp_brief" <<'EOF'
# Task Brief

- Goal: temporary selftest fixture
- Change classification: process-surface
- Change type: none
- Files in scope: none
- Out of scope: none
- Known facts: none
- Open questions / assumptions: none
- Risks to check: none
- Required roles: none
- Optional roles: none
- Default writer role: none
- Write permissions: none
- Non-goals: none
- Acceptance checks: none
- Semantic review dimensions: none
- Source-of-truth docs: none
- External sources required: none
- Critical assumptions to prove or reject: none
- Required output fields: none
- Review note impact: no
- If blocked: stop and report the docs contract failure
EOF

set +e
output="$(CHECK_DOCS_PLAN_DIR="$plan_dir" npm run docs:check 2>&1)"
status=$?
set -e

if [ "$status" -eq 0 ]; then
    echo "Expected docs:check to fail when a Task Brief is placed under the configured planning directory"
    exit 1
fi

if ! printf '%s\n' "$output" | grep -qi "Task Brief"; then
    echo "Expected docs:check failure output to reference misplaced Task Brief artifacts"
    printf '%s\n' "$output"
    exit 1
fi

echo "check-docs-task-brief-artifacts selftest: PASS"
