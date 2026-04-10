#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

tmp_dir="$(mktemp -d)"
changed_spec_file="docs/superpowers/specs/__check_spec_reviewer_evidence_fixture__.md"
task_brief_file="docs/task-briefs/2026-04-10-check-spec-reviewer-evidence-task-brief.md"
writer_agent_report_file="docs/agent-reports/2026-04-10-check-spec-reviewer-evidence-writer.md"
spec_reviewer_report_file="docs/agent-reports/2026-04-10-check-spec-reviewer-evidence-reviewer.md"
changed_spec_files_path="$tmp_dir/changed-spec-files.txt"
changed_brief_files_path="$tmp_dir/changed-brief-files.txt"

cleanup() {
    rm -rf "$tmp_dir"
    rm -f "$changed_spec_file" "$task_brief_file" "$writer_agent_report_file" "$spec_reviewer_report_file"
}
trap cleanup EXIT

mkdir -p "$(dirname "$changed_spec_file")" "$(dirname "$task_brief_file")" "$(dirname "$writer_agent_report_file")"

cat > "$changed_spec_file" <<'EOF'
# Spec reviewer evidence fixture

- Goal: exercise spec surface evidence checks
EOF

cat > "$task_brief_file" <<EOF
# Task Brief

- Goal: check spec reviewer evidence selftest
- Change classification: process-surface
- Change classification rationale: spec surface evidence contract selftest
- Change type: none
- Files in scope: $changed_spec_file
- Out of scope: none
- Known facts: spec surface evidence is required
- Open questions / assumptions: none
- Risks to check: stale or missing spec reviewer evidence
- Required roles: process-implementer, spec-reviewer, verifier
- Optional roles: none
- Verifier profile: light
- Default writer role: process-implementer
- Implementation owner: process-implementer
- Artifact type: spec
- Spec review required: yes
- Spec artifact paths: $changed_spec_file
- Write permissions: $changed_spec_file
- Writer dispatch backend: native-codex-subagents
- Writer dispatch target: .codex/agents/process-implementer.toml
- Writer dispatch scope: $changed_spec_file
- Non-goals: none
- Acceptance checks: spec reviewer evidence must be fresh
- Required verifier commands: npm run docs:check; npm run process:selftest
- Required artifacts: Task Brief, writer evidence, spec review evidence, verifier evidence
- Review note required: no
- Semantic review dimensions: none
- Source-of-truth docs: docs/process/change-matrix.md
- External sources required: none
- Critical assumptions to prove or reject: none
- Required output fields: none
- Review note impact: no
- If blocked: stop and report the failing evidence link
EOF

cat > "$writer_agent_report_file" <<EOF
# Agent Report

- Role: process-implementer
- Summary: wrote the scoped spec artifact
- Task Brief path: $task_brief_file
- Scope / ownership respected: yes
- Files touched/reviewed: $changed_spec_file
- Findings: none
- Required follow-up: spec-reviewer -> verifier
- Commands run: npm run docs:check
- Evidence: selftest writer evidence
- Residual risks: verifier still pending
EOF

sleep 1

cat > "$spec_reviewer_report_file" <<EOF
# Agent Report

- Role: spec-reviewer
- Summary: reviewed the scoped spec artifact
- Task Brief path: $task_brief_file
- Scope / ownership respected: yes
- Files touched/reviewed: $changed_spec_file
- Findings: none
- Required follow-up: verifier
- Commands run: reviewed docs/process/change-matrix.md
- Evidence: selftest spec reviewer evidence
- Residual risks: verifier still pending
EOF

cat > "$changed_spec_files_path" <<EOF
$changed_spec_file
EOF

cat > "$changed_brief_files_path" <<EOF
$task_brief_file
EOF

path_output="$(QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_spec_files_path" bash ./script/process/check-spec-reviewer-evidence.sh 2>&1)"
if ! printf '%s\n' "$path_output" | grep -q "\[check-spec-reviewer-evidence\] PASS"; then
    echo "Expected path-based spec surface evidence check to pass"
    printf '%s\n' "$path_output"
    exit 1
fi

brief_output="$(QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_brief_files_path" bash ./script/process/check-spec-reviewer-evidence.sh 2>&1)"
if ! printf '%s\n' "$brief_output" | grep -q "\[check-spec-reviewer-evidence\] PASS"; then
    echo "Expected brief-declared spec surface evidence check to pass"
    printf '%s\n' "$brief_output"
    exit 1
fi

sed -i 's|npm run docs:check; npm run process:selftest|npm run docs:check|' "$task_brief_file"
set +e
missing_metadata_output="$(QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_brief_files_path" bash ./script/process/check-spec-reviewer-evidence.sh 2>&1)"
missing_metadata_status=$?
set -e
if [ "$missing_metadata_status" -eq 0 ]; then
    echo "Expected spec reviewer evidence check to fail when spec verifier commands metadata is incomplete"
    printf '%s\n' "$missing_metadata_output"
    exit 1
fi
if ! printf '%s\n' "$missing_metadata_output" | grep -q "Required verifier commands"; then
    echo "Expected missing metadata failure to reference Required verifier commands"
    printf '%s\n' "$missing_metadata_output"
    exit 1
fi

sed -i 's|Required verifier commands: npm run docs:check|Required verifier commands: npm run docs:check; npm run process:selftest|' "$task_brief_file"
sleep 1
touch "$changed_spec_file"
set +e
stale_output="$(QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_brief_files_path" bash ./script/process/check-spec-reviewer-evidence.sh 2>&1)"
stale_status=$?
set -e
if [ "$stale_status" -eq 0 ]; then
    echo "Expected spec reviewer evidence check to fail when the reviewer report is stale"
    printf '%s\n' "$stale_output"
    exit 1
fi
if ! printf '%s\n' "$stale_output" | grep -qi "stale"; then
    echo "Expected stale spec reviewer evidence failure to mention stale"
    printf '%s\n' "$stale_output"
    exit 1
fi

echo "check-spec-reviewer-evidence selftest: PASS"
