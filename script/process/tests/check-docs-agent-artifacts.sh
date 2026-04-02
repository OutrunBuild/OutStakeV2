#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

tmp_dir="$(mktemp -d)"
plan_dir="$tmp_dir/plans"
tmp_report="$plan_dir/zz-temp-agent-report-for-selftest.md"

cleanup() {
    rm -rf "$tmp_dir"
}
trap cleanup EXIT

mkdir -p "$plan_dir"

cat > "$tmp_report" <<'EOF'
# Agent Report

- Role: verifier
- Summary: temporary selftest fixture
- Files touched/reviewed: none
- Findings: none
- Required follow-up: none
- Commands run: none
- Evidence: none
- Residual risks: none
EOF

set +e
output="$(CHECK_DOCS_PLAN_DIR="$plan_dir" npm run docs:check 2>&1)"
status=$?
set -e

if [ "$status" -eq 0 ]; then
    echo "Expected docs:check to fail when an Agent Report is placed under the configured planning directory"
    exit 1
fi

if ! printf '%s\n' "$output" | grep -qi "Agent Report"; then
    echo "Expected docs:check failure output to reference misplaced Agent Report artifacts"
    printf '%s\n' "$output"
    exit 1
fi

echo "check-docs-agent-artifacts selftest: PASS"
