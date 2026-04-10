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
    "default_roles": [
      "solidity-implementer",
      "process-implementer",
      "spec-reviewer",
      "logic-reviewer",
      "security-reviewer",
      "gas-reviewer",
      "verifier"
    ],
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
  "quality_gate": {
    "spec_default_roles": [
      "process-implementer",
      "spec-reviewer",
      "verifier"
    ]
  },
  "follow_up_brief": {
    "trigger_artifact_field": "Trigger artifact",
    "trigger_stale_findings_field": "Trigger stale findings"
  },
  "workflow": {
    "artifact_sequences": {
      "spec_surface": [
        "Task Brief",
        "Agent Report",
        "spec review evidence",
        "verifier evidence",
        "docs:check",
        "process:selftest"
      ]
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

spec_default_roles_json="$(PROCESS_POLICY_FILE="$policy_file" node ./script/process/read-process-config.js policy quality_gate.spec_default_roles --lines)"
if ! printf '%s\n' "$spec_default_roles_json" | grep -qx 'spec-reviewer'; then
    echo "Expected quality_gate.spec_default_roles to include spec-reviewer"
    exit 1
fi

workflow_spec_sequence="$(PROCESS_POLICY_FILE="$policy_file" node ./script/process/read-process-config.js policy workflow.artifact_sequences.spec_surface --lines)"
if ! printf '%s\n' "$workflow_spec_sequence" | grep -qx 'spec review evidence'; then
    echo "Expected workflow.artifact_sequences.spec_surface to include spec review evidence"
    exit 1
fi

if printf '%s\n' "$workflow_spec_sequence" | grep -qx 'codex review'; then
    echo "Did not expect workflow.artifact_sequences.spec_surface to include codex review"
    exit 1
fi

if ! printf '%s\n' "$workflow_spec_sequence" | grep -qx 'docs:check'; then
    echo "Expected workflow.artifact_sequences.spec_surface to include docs:check"
    exit 1
fi

if ! printf '%s\n' "$workflow_spec_sequence" | grep -qx 'process:selftest'; then
    echo "Expected workflow.artifact_sequences.spec_surface to include process:selftest"
    exit 1
fi

agent_default_roles="$(PROCESS_POLICY_FILE="$policy_file" node ./script/process/read-process-config.js policy agents.default_roles --lines)"
if ! printf '%s\n' "$agent_default_roles" | grep -qx 'spec-reviewer'; then
    echo "Expected agents.default_roles to include spec-reviewer"
    exit 1
fi

trigger_artifact_field="$(PROCESS_POLICY_FILE="$policy_file" node ./script/process/read-process-config.js policy follow_up_brief.trigger_artifact_field)"
if [ "$trigger_artifact_field" != "Trigger artifact" ]; then
    echo "Expected policy-driven follow-up trigger artifact field resolution to work"
    exit 1
fi

trigger_findings_field="$(PROCESS_POLICY_FILE="$policy_file" node ./script/process/read-process-config.js policy follow_up_brief.trigger_stale_findings_field)"
if [ "$trigger_findings_field" != "Trigger stale findings" ]; then
    echo "Expected policy-driven follow-up trigger findings field resolution to work"
    exit 1
fi

echo "process-policy selftest: PASS"
