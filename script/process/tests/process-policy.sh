#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

tmp_dir="$(mktemp -d)"
policy_file="$tmp_dir/policy.json"

cleanup() {
    rm -rf "$tmp_dir"
}
trap cleanup EXIT

cat > "$policy_file" <<'EOF'
{
  "agents": {
    "main_session_role": "main-orchestrator",
    "agent_report_directory": "docs/agent-reports",
    "task_brief_directory": "docs/task-briefs",
    "main_session_forbidden_write_patterns": [
      "^src/.*\\.sol$",
      "^script/process/.*$"
    ],
    "require_task_brief_before_write_patterns": [
      "^src/.*\\.sol$"
    ],
    "required_writer_for_patterns": {
      "^src/.*\\.sol$": "solidity-implementer",
      "^script/process/.*$": "process-implementer"
    }
  },
  "solidity_review_note": {
    "required_fields": [
      "Task Brief path",
      "Agent Report path",
      "Implementation owner",
      "Writer dispatch confirmed"
    ]
  }
}
EOF

main_session_role="$(PROCESS_POLICY_FILE="$policy_file" node ./script/process/read-process-config.js policy agents.main_session_role)"
if [ "$main_session_role" != "main-orchestrator" ]; then
    echo "Expected policy-driven main session role resolution to work"
    exit 1
fi

writer_role_json="$(PROCESS_POLICY_FILE="$policy_file" node ./script/process/read-process-config.js policy agents.required_writer_for_patterns)"
if ! printf '%s\n' "$writer_role_json" | grep -q 'solidity-implementer'; then
    echo "Expected policy-driven required writer map resolution to work"
    exit 1
fi

if ! printf '%s\n' "$writer_role_json" | grep -q 'process-implementer'; then
    echo "Expected process JS surfaces to resolve to process-implementer"
    exit 1
fi

forbidden_patterns_json="$(PROCESS_POLICY_FILE="$policy_file" node ./script/process/read-process-config.js policy agents.main_session_forbidden_write_patterns)"
if ! printf '%s\n' "$forbidden_patterns_json" | grep -q 'script/process/.*'; then
    echo "Expected script/process surfaces to be forbidden for the main session"
    exit 1
fi

agent_report_directory="$(PROCESS_POLICY_FILE="$policy_file" node ./script/process/read-process-config.js policy agents.agent_report_directory)"
if [ "$agent_report_directory" != "docs/agent-reports" ]; then
    echo "Expected policy-driven agent report directory resolution to work"
    exit 1
fi

task_brief_directory="$(PROCESS_POLICY_FILE="$policy_file" node ./script/process/read-process-config.js policy agents.task_brief_directory)"
if [ "$task_brief_directory" != "docs/task-briefs" ]; then
    echo "Expected policy-driven task brief directory resolution to work"
    exit 1
fi

echo "process-policy selftest: PASS"
