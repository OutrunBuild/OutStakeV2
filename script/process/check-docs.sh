#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

required_files=(
    "AGENTS.md"
    ".codex/runtime/subagent-runtime.json"
    ".codex/workflows/solidity-subagent-workflow.json"
    ".codex/agents/process-implementer.toml"
    ".codex/agents/process-implementer.md"
    ".codex/agents/logic-reviewer.toml"
    ".codex/agents/logic-reviewer.md"
    ".codex/agents/solidity-implementer.toml"
    ".codex/agents/solidity-implementer.md"
    ".codex/agents/security-reviewer.toml"
    ".codex/agents/security-reviewer.md"
    ".codex/agents/gas-reviewer.toml"
    ".codex/agents/gas-reviewer.md"
    ".codex/agents/verifier.toml"
    ".codex/agents/verifier.md"
    ".codex/agents/spec-reviewer.toml"
    ".codex/agents/spec-reviewer.md"
    ".claude/agents/spec-reviewer.md"
    ".claude/rules/spec-surface.md"
    ".codex/agents/solidity-explorer.toml"
    ".codex/agents/solidity-explorer.md"
    ".codex/agents/security-test-writer.toml"
    ".codex/agents/security-test-writer.md"
    ".codex/templates/task-brief.md"
    ".codex/templates/role-delta-brief.md"
    ".codex/templates/follow-up-brief.md"
    ".codex/templates/agent-report.md"
    ".githooks/pre-commit"
    ".githooks/pre-push"
    ".github/pull_request_template.md"
    ".github/workflows/test.yml"
    ".solhint.json"
    ".solhintignore"
    "script/process/check-docs.sh"
    "script/process/run-codex-review.sh"
    "script/process/run-stale-evidence-loop.sh"
    "script/process/run-pre-push-quality-gate.sh"
    "script/process/check-coverage.js"
    "script/process/check-coverage.sh"
    "script/process/check-review-note.sh"
    "script/process/check-solidity-review-note.sh"
    "script/process/check-spec-reviewer-evidence.sh"
    "script/process/check-spec-reviewer-report.sh"
    "script/process/quality-quick.sh"
    "script/process/quality-gate.sh"
    "script/process/tests/run-all.sh"
    "docs/process/README.md"
    "docs/process/change-matrix.md"
    "docs/process/agents-detail.md"
    "docs/process/review-notes.md"
    "docs/process/policy.json"
    "docs/reviews/README.md"
    "docs/reviews/TEMPLATE.md"
    "docs/task-briefs/README.md"
    "docs/agent-reports/README.md"
    # spec documents
    "docs/spec/protocol.md"
    "docs/spec/state-machines.md"
    "docs/spec/accounting.md"
    "docs/spec/access-control.md"
    "docs/spec/common-foundations.md"
    "docs/spec/router-and-user-flows.md"
    "docs/spec/deployment.md"
    "docs/spec/yield-adapters.md"
    "docs/spec/oracles-and-integrations.md"
    "docs/spec/testing-and-evidence.md"
    "docs/spec/implementation-map.md"
    "package.json"
    "package-lock.json"
)

required_dirs=(
    ".codex/agents"
    ".codex/runtime"
    ".codex/templates"
    ".github/workflows"
    "docs/process"
    "docs/reviews"
    "docs/task-briefs"
    "docs/agent-reports"
    "docs/superpowers/specs"
    "docs/superpowers/plans"
)

for directory in "${required_dirs[@]}"; do
    if [ ! -d "$directory" ]; then
        echo "[check-docs] ERROR: missing required directory: $directory"
        exit 1
    fi
done

for file in "${required_files[@]}"; do
    if [ ! -f "$file" ]; then
        echo "[check-docs] ERROR: missing required file: $file"
        exit 1
    fi

    if [ ! -s "$file" ]; then
        echo "[check-docs] ERROR: required file is empty: $file"
        exit 1
    fi
done

if ! command -v python3 >/dev/null 2>&1; then
    echo "[check-docs] ERROR: python3 is required to validate agent manifests"
    exit 1
fi

python3 - <<'PY'
from pathlib import Path
import sys
import tomllib

if sys.version_info < (3, 11):
    print("[check-docs] ERROR: python3.11+ is required to validate agent manifests with tomllib", file=sys.stderr)
    sys.exit(1)

agent_dir = Path(".codex/agents")
toml_files = sorted(agent_dir.glob("*.toml"))
md_files = sorted(path for path in agent_dir.glob("*.md") if path.name not in ("README.md", "_shared-contract.md"))

if not toml_files:
    print("[check-docs] ERROR: no agent manifest files found under .codex/agents", file=sys.stderr)
    sys.exit(1)

required_keys = {"name", "description", "developer_instructions"}
required_sections = [
    "## Role",
    "## Use This Role When",
    "## Do Not Use This Role When",
    "## Inputs Required",
    "## Allowed Writes",
    "## Read Scope",
    "## Execution Checklist",
    "## Decision / Block Semantics",
    "## Output Contract",
    "## Review Note Mapping",
    "## Escalation Rules",
]

for path in toml_files:
    with path.open("rb") as handle:
        document = tomllib.load(handle)

    missing = sorted(required_keys - document.keys())
    if missing:
        print(f"[check-docs] ERROR: agent manifest {path} is missing keys: {', '.join(missing)}", file=sys.stderr)
        sys.exit(1)

    if document["name"] != path.stem:
        print(f"[check-docs] ERROR: agent manifest {path} has name '{document['name']}' but expected '{path.stem}'", file=sys.stderr)
        sys.exit(1)

    counterpart = path.with_suffix(".md")
    if not counterpart.is_file():
        print(f"[check-docs] ERROR: agent manifest {path} is missing runtime contract {counterpart}", file=sys.stderr)
        sys.exit(1)

    expected_contract_ref = counterpart.as_posix()
    instructions = str(document["developer_instructions"])
    if expected_contract_ref not in instructions:
        print(
            f"[check-docs] ERROR: agent manifest {path} must reference its runtime contract {expected_contract_ref}",
            file=sys.stderr,
        )
        sys.exit(1)

for path in md_files:
    counterpart = path.with_suffix(".toml")
    if not counterpart.is_file():
        print(f"[check-docs] ERROR: runtime contract {path} is missing manifest {counterpart}", file=sys.stderr)
        sys.exit(1)

    text = path.read_text()
    missing_sections = [section for section in required_sections if section not in text]
    if missing_sections:
        print(
            f"[check-docs] ERROR: runtime contract {path} is missing sections: {', '.join(missing_sections)}",
            file=sys.stderr,
        )
        sys.exit(1)

    lines = text.splitlines()
    headings = []
    for index, line in enumerate(lines):
        if line.startswith("## "):
            headings.append((line.strip(), index))

    heading_map = {heading: index for heading, index in headings}
    ordered_headings = [heading for heading, _ in headings]

    for section in required_sections:
        start = heading_map[section]
        next_index = len(lines)
        current_pos = ordered_headings.index(section)
        if current_pos + 1 < len(ordered_headings):
            next_heading = ordered_headings[current_pos + 1]
            next_index = heading_map[next_heading]

        body = "\n".join(lines[start + 1:next_index]).strip()
        if not body:
            print(f"[check-docs] ERROR: runtime contract {path} has empty section body for {section}", file=sys.stderr)
            sys.exit(1)
PY

mapfile -t workflow_files < <(find .github/workflows -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) | sort)

if [ "${#workflow_files[@]}" -eq 0 ]; then
    echo "[check-docs] ERROR: no workflow files found under .github/workflows"
    exit 1
fi

node - "${workflow_files[@]}" <<'EOF'
const fs = require('fs');
const yaml = require('js-yaml');

const files = process.argv.slice(2);

function fail(message) {
  console.error(`[check-docs] ERROR: ${message}`);
  process.exit(1);
}

for (const file of files) {
  let document;
  try {
    document = yaml.load(fs.readFileSync(file, 'utf8'));
  } catch (error) {
    fail(`workflow YAML parse failed for ${file}: ${error.message}`);
  }

  if (!document || typeof document !== 'object' || Array.isArray(document)) {
    fail(`workflow must be a mapping at ${file}`);
  }

  if (!Object.prototype.hasOwnProperty.call(document, 'on')) {
    fail(`workflow is missing top-level 'on' in ${file}`);
  }

  if (!document.jobs || typeof document.jobs !== 'object' || Array.isArray(document.jobs)) {
    fail(`workflow is missing top-level 'jobs' mapping in ${file}`);
  }

  for (const [jobName, job] of Object.entries(document.jobs)) {
    if (!job || typeof job !== 'object' || Array.isArray(job)) {
      fail(`workflow job '${jobName}' must be a mapping in ${file}`);
    }

    const hasReusableWorkflow = typeof job.uses === 'string' && job.uses.trim() !== '';
    const hasStandardRunner = Object.prototype.hasOwnProperty.call(job, 'runs-on');
    const hasStandardSteps = Array.isArray(job.steps) && job.steps.length > 0;

    if (hasReusableWorkflow) {
      continue;
    }

    if (!hasStandardRunner) {
      fail(`workflow job '${jobName}' must define either job-level 'uses' or 'runs-on' in ${file}`);
    }

    if (!hasStandardSteps) {
      fail(`workflow job '${jobName}' using 'runs-on' must define a non-empty 'steps' array in ${file}`);
    }
  }
}
EOF

node - <<'EOF'
const fs = require('fs');

const packageJson = JSON.parse(fs.readFileSync('package.json', 'utf8'));
const policy = JSON.parse(fs.readFileSync('docs/process/policy.json', 'utf8'));
const runtime = JSON.parse(fs.readFileSync('.codex/runtime/subagent-runtime.json', 'utf8'));
const workflow = JSON.parse(fs.readFileSync('.codex/workflows/solidity-subagent-workflow.json', 'utf8'));
const taskBriefTemplate = fs.readFileSync('.codex/templates/task-brief.md', 'utf8');
const followUpBriefTemplate = fs.readFileSync('.codex/templates/follow-up-brief.md', 'utf8');
const agentReportTemplate = fs.readFileSync('.codex/templates/agent-report.md', 'utf8');
const claudeSpecReviewerContract = fs.readFileSync('.claude/agents/spec-reviewer.md', 'utf8');
const claudeSpecSurfaceRules = fs.readFileSync('.claude/rules/spec-surface.md', 'utf8');
const claudeRequiredSections = [
  "## 角色",
  "## 适用场景",
  "## 不适用场景",
  "## Inputs",
  "## 允许写入",
  "## 读取范围",
  "## 执行清单",
  "## 决策规则",
  "## 输出",
  "## Review Note Mapping",
  "## 升级规则",
  "## 不需要读的文件",
];
const scripts = packageJson.scripts || {};
const requiredScripts = [
  'docs:check',
  'process:selftest',
  'coverage:check',
  'quality:quick',
  'quality:gate',
  'classify:change',
  'codex:review',
  'stale-evidence:loop',
];

for (const scriptName of requiredScripts) {
  if (typeof scripts[scriptName] !== 'string' || scripts[scriptName].trim() === '') {
    console.error(`[check-docs] ERROR: package.json is missing required npm script '${scriptName}'`);
    process.exit(1);
  }
}

if (policy.agents.workflow_index !== '.codex/workflows/solidity-subagent-workflow.json') {
  console.error('[check-docs] ERROR: policy agents.workflow_index must point at .codex/workflows/solidity-subagent-workflow.json');
  process.exit(1);
}

if (runtime.workflow_index !== policy.agents.workflow_index) {
  console.error('[check-docs] ERROR: runtime workflow_index must match policy agents.workflow_index');
  process.exit(1);
}

for (const key of ['task_brief_directory', 'agent_report_directory', 'task_brief_template', 'agent_report_template', 'agent_directory']) {
  if (String(policy.agents[key]) !== String(runtime.artifacts[key])) {
    console.error(`[check-docs] ERROR: runtime.artifacts.${key} must match policy.agents.${key}`);
    process.exit(1);
  }
  if (String(policy.agents[key]) !== String(workflow.artifacts[key])) {
    console.error(`[check-docs] ERROR: workflow.artifacts.${key} must match policy.agents.${key}`);
    process.exit(1);
  }
}

for (const key of ['main_session_role']) {
  if (String(policy.agents[key]) !== String(runtime.roles[key])) {
    console.error(`[check-docs] ERROR: runtime.roles.${key} must match policy.agents.${key}`);
    process.exit(1);
  }
  if (String(policy.agents[key]) !== String(workflow.roles[key])) {
    console.error(`[check-docs] ERROR: workflow.roles.${key} must match policy.agents.${key}`);
    process.exit(1);
  }
}

for (const key of ['default_roles', 'on_demand_roles']) {
  if (JSON.stringify(policy.agents[key]) !== JSON.stringify(runtime.roles[key])) {
    console.error(`[check-docs] ERROR: runtime.roles.${key} must match policy.agents.${key}`);
    process.exit(1);
  }
  if (JSON.stringify(policy.agents[key]) !== JSON.stringify(workflow.roles[key])) {
    console.error(`[check-docs] ERROR: workflow.roles.${key} must match policy.agents.${key}`);
    process.exit(1);
  }
}

if (!policy.agents.default_roles.includes('spec-reviewer')) {
  console.error('[check-docs] ERROR: policy.agents.default_roles must include spec-reviewer');
  process.exit(1);
}

if (JSON.stringify(policy.quality_gate.spec_default_roles) !== JSON.stringify(['process-implementer', 'spec-reviewer', 'verifier'])) {
  console.error('[check-docs] ERROR: quality_gate.spec_default_roles must be ["process-implementer","spec-reviewer","verifier"]');
  process.exit(1);
}

if (!Array.isArray(policy.workflow?.artifact_sequences?.spec_surface) || JSON.stringify(policy.workflow.artifact_sequences.spec_surface) !== JSON.stringify([
  'Task Brief',
  'writer evidence',
  'spec review evidence',
  'verifier evidence',
  'docs:check',
  'process:selftest',
])) {
  console.error('[check-docs] ERROR: workflow.artifact_sequences.spec_surface must describe the spec-reviewer evidence chain');
  process.exit(1);
}

if (!Array.isArray(runtime.roles.default_roles) || !runtime.roles.default_roles.includes('spec-reviewer')) {
  console.error('[check-docs] ERROR: runtime.roles.default_roles must include spec-reviewer');
  process.exit(1);
}

if (!Array.isArray(workflow.roles.default_roles) || !workflow.roles.default_roles.includes('spec-reviewer')) {
  console.error('[check-docs] ERROR: workflow.roles.default_roles must include spec-reviewer');
  process.exit(1);
}

for (const field of ['Artifact type', 'Spec review required', 'Spec artifact paths']) {
  if (!Array.isArray(policy.task_brief.required_fields) || !policy.task_brief.required_fields.includes(field)) {
    console.error(`[check-docs] ERROR: policy.task_brief.required_fields must include ${field}`);
    process.exit(1);
  }
  if (!Array.isArray(policy.follow_up_brief.required_fields) || !policy.follow_up_brief.required_fields.includes(field)) {
    console.error(`[check-docs] ERROR: policy.follow_up_brief.required_fields must include ${field}`);
    process.exit(1);
  }
}

for (const requiredField of ['- Change classification rationale:', '- Verifier profile:', '- Implementation owner:', '- Writer dispatch backend:', '- Required verifier commands:', '- Required artifacts:']) {
  if (!taskBriefTemplate.includes(requiredField)) {
    console.error(`[check-docs] ERROR: task brief template is missing required field ${requiredField}`);
    process.exit(1);
  }
}

for (const requiredField of ['- Artifact type:', '- Spec review required:', '- Spec artifact paths:']) {
  if (!taskBriefTemplate.includes(requiredField)) {
    console.error(`[check-docs] ERROR: task brief template is missing required field ${requiredField}`);
    process.exit(1);
  }
  if (!followUpBriefTemplate.includes(requiredField)) {
    console.error(`[check-docs] ERROR: follow-up brief template is missing required field ${requiredField}`);
    process.exit(1);
  }
}

for (const requiredField of ['- Trigger artifact:', '- Trigger stale findings:']) {
  if (!followUpBriefTemplate.includes(requiredField)) {
    console.error(`[check-docs] ERROR: follow-up brief template is missing required field ${requiredField}`);
    process.exit(1);
  }
}

for (const requiredSection of claudeRequiredSections) {
  if (!claudeSpecReviewerContract.includes(requiredSection)) {
    console.error(`[check-docs] ERROR: .claude/agents/spec-reviewer.md is missing section ${requiredSection}`);
    process.exit(1);
  }
}

for (const requiredPhrase of [
  'docs/spec/**',
  'docs/superpowers/specs/**',
  'spec review evidence',
]) {
  if (!claudeSpecReviewerContract.includes(requiredPhrase)) {
    console.error(`[check-docs] ERROR: .claude/agents/spec-reviewer.md is missing required phrase ${requiredPhrase}`);
    process.exit(1);
  }
}

for (const requiredPhrase of [
  'docs/spec/**',
  'docs/superpowers/specs/**',
  'spec-reviewer',
  'npm run docs:check',
  'spec review evidence',
]) {
  if (!claudeSpecSurfaceRules.includes(requiredPhrase)) {
    console.error(`[check-docs] ERROR: .claude/rules/spec-surface.md is missing required phrase ${requiredPhrase}`);
    process.exit(1);
  }
}

for (const key of ['role_delta_brief_template', 'follow_up_brief_template']) {
  if (String(policy.agents[key]) !== String(runtime.agents[key])) {
    console.error(`[check-docs] ERROR: runtime.agents.${key} must match policy.agents.${key}`);
    process.exit(1);
  }
  if (String(policy.agents[key]) !== String(workflow.agents[key])) {
    console.error(`[check-docs] ERROR: workflow.agents.${key} must match policy.agents.${key}`);
    process.exit(1);
  }
}

if (!policy.change_classifier || !policy.change_classifier.role_matrix) {
  console.error('[check-docs] ERROR: policy must define change_classifier.role_matrix');
  process.exit(1);
}

for (const requiredField of ['- Task Brief path:', '- Scope / ownership respected:']) {
  if (!agentReportTemplate.includes(requiredField)) {
    console.error(`[check-docs] ERROR: agent report template is missing required field ${requiredField}`);
    process.exit(1);
  }
}
EOF

planning_surfaces=()

if [ -n "${CHECK_DOCS_PLAN_DIR:-}" ]; then
    planning_surfaces+=("${CHECK_DOCS_PLAN_DIR}")
else
    planning_surfaces=(
        "docs/superpowers/specs"
        "docs/superpowers/plans"
    )
fi

for planning_dir in "${planning_surfaces[@]}"; do
    [ -d "$planning_dir" ] || continue

    while IFS= read -r misplaced_report; do
        if [ -n "$misplaced_report" ]; then
            echo "[check-docs] ERROR: Agent Report must not live under ${planning_dir}: $misplaced_report"
            exit 1
        fi
    done < <(find "$planning_dir" -maxdepth 1 -type f -name '*.md' -print0 | xargs -0 -r grep -l '^# Agent Report$')

    while IFS= read -r misplaced_brief; do
        if [ -n "$misplaced_brief" ]; then
            echo "[check-docs] ERROR: Task Brief must not live under ${planning_dir}: $misplaced_brief"
            exit 1
        fi
    done < <(find "$planning_dir" -maxdepth 1 -type f -name '*.md' -print0 | xargs -0 -r grep -l '^# Task Brief$')
done

echo "[check-docs] PASS"
