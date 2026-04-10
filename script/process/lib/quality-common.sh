#!/usr/bin/env bash

read_policy_value() {
    local key="$1"
    local default_value="${2-}"
    local value

    if [ "$#" -ge 2 ]; then
        if value="$(node ./script/process/read-process-config.js policy "$key" 2>/dev/null)"; then
            printf '%s' "$value"
            return
        fi

        printf '%s' "$default_value"
        return
    fi

    node ./script/process/read-process-config.js policy "$key"
}

read_policy_lines() {
    node ./script/process/read-process-config.js policy "$1" --lines
}

read_policy_lines_or_default() {
    local key="$1"
    shift
    local output

    if output="$(node ./script/process/read-process-config.js policy "$key" --lines 2>/dev/null)"; then
        printf '%s\n' "$output"
        return
    fi

    printf '%s\n' "$@"
}

load_file_list_from_ci() {
    if [ -n "${QUALITY_GATE_FILE_LIST:-}" ] && [ -f "${QUALITY_GATE_FILE_LIST}" ]; then
        cat "${QUALITY_GATE_FILE_LIST}"
        return
    fi

    if [ -n "${GITHUB_BASE_REF:-}" ]; then
        if ! git rev-parse --verify "origin/${GITHUB_BASE_REF}" >/dev/null 2>&1; then
            git fetch --no-tags --prune origin "${GITHUB_BASE_REF}:${GITHUB_BASE_REF}"
            git branch --set-upstream-to "origin/${GITHUB_BASE_REF}" "${GITHUB_BASE_REF}" >/dev/null 2>&1 || true
        fi
        git diff --name-only "origin/${GITHUB_BASE_REF}...HEAD"
        return
    fi

    if git rev-parse --verify HEAD~1 >/dev/null 2>&1; then
        git diff --name-only HEAD~1..HEAD
        return
    fi

    git ls-files
}

quality_cleanup_paths=()

quality_register_cleanup_path() {
    quality_cleanup_paths+=("$1")
}

quality_cleanup() {
    local path
    for path in "${quality_cleanup_paths[@]}"; do
        [ -n "$path" ] || continue
        [ -e "$path" ] || continue
        rm -f "$path"
    done
}

quality_initialize_runtime() {
    repo_root="$(git rev-parse --show-toplevel)"
    cd "$repo_root"

    mode="${QUALITY_GATE_MODE:-staged}"
    workflow_changed_files=""

    if [ -n "${QUALITY_GATE_FILE_LIST:-}" ] && [ -f "${QUALITY_GATE_FILE_LIST}" ]; then
        changed_files="$(cat "${QUALITY_GATE_FILE_LIST}")"
    elif [ "$mode" = "ci" ]; then
        changed_files="$(load_file_list_from_ci)"
    else
        changed_files="$(git diff --cached --name-only --diff-filter=ACMRD)"
    fi

    if [ -n "${QUALITY_GATE_CHANGESET_FILE_LIST:-}" ] && [ -f "${QUALITY_GATE_CHANGESET_FILE_LIST}" ]; then
        workflow_changed_files="$(cat "${QUALITY_GATE_CHANGESET_FILE_LIST}")"
    else
        workflow_changed_files="$changed_files"
    fi
}

quality_exit_if_no_changed_files() {
    local label="$1"
    if [ -z "$changed_files" ]; then
        echo "[$label] no files to check, skipping."
        exit 0
    fi
}

quality_prepare_changed_files_tmp() {
    changed_files_tmp="$(mktemp)"
    quality_register_cleanup_path "$changed_files_tmp"
    trap quality_cleanup EXIT
    printf '%s\n' "$changed_files" > "$changed_files_tmp"
}

quality_prepare_workflow_changed_files_tmp() {
    workflow_changed_files_tmp="$(mktemp)"
    quality_register_cleanup_path "$workflow_changed_files_tmp"
    trap quality_cleanup EXIT
    printf '%s\n' "$workflow_changed_files" > "$workflow_changed_files_tmp"
}

read_classifier_field() {
    local field="$1"
    CLASSIFICATION_JSON="$classification_json" node -e '
const document = JSON.parse(process.env.CLASSIFICATION_JSON || "{}");
const field = process.argv[1];
let value = document;
for (const key of field.split(".")) {
  if (key === "") continue;
  if (value == null || !Object.prototype.hasOwnProperty.call(value, key)) {
    process.exit(1);
  }
  value = value[key];
}
if (typeof value === "object") {
  process.stdout.write(JSON.stringify(value));
} else {
  process.stdout.write(String(value));
}
' "$field"
}

quality_file_declares_spec_surface() {
    local candidate="$1"

    TASK_BRIEF_DIRECTORY="$task_brief_directory" \
    AGENT_REPORT_DIRECTORY="$agent_report_directory" \
    node - "$candidate" <<'EOF'
const fs = require('fs');

const candidate = process.argv[2];
const taskBriefDirectory = process.env.TASK_BRIEF_DIRECTORY || 'docs/task-briefs';
const agentReportDirectory = process.env.AGENT_REPORT_DIRECTORY || 'docs/agent-reports';

function extractField(document, field) {
  const prefix = `- ${field}:`;
  const lines = document.split(/\r?\n/);
  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index];
    if (!line.startsWith(prefix)) continue;

    let value = line.slice(prefix.length).trim();
    for (let cursor = index + 1; cursor < lines.length; cursor += 1) {
      const next = lines[cursor];
      if (/^- [^:]+:/.test(next)) break;
      if (next.startsWith('  ') || next === '') {
        value += `\n${next}`;
        continue;
      }
      break;
    }
    return value.trim();
  }
  return '';
}

function isSpecBrief(document) {
  const artifactType = extractField(document, 'Artifact type').trim().toLowerCase();
  const specReviewRequired = extractField(document, 'Spec review required').trim().toLowerCase();
  return artifactType === 'spec' || specReviewRequired === 'yes';
}

if (!candidate || !fs.existsSync(candidate) || !fs.statSync(candidate).isFile()) {
  process.exit(1);
}

const document = fs.readFileSync(candidate, 'utf8');
if ((candidate.startsWith(`${taskBriefDirectory}/`) || document.startsWith('# Task Brief') || document.startsWith('# Follow-up Brief')) && isSpecBrief(document)) {
  process.exit(0);
}

if (candidate.startsWith(`${agentReportDirectory}/`) && document.startsWith('# Agent Report')) {
  const taskBriefPath = extractField(document, 'Task Brief path').trim();
  if (!taskBriefPath || !fs.existsSync(taskBriefPath)) {
    process.exit(1);
  }

  const taskBrief = fs.readFileSync(taskBriefPath, 'utf8');
  if (isSpecBrief(taskBrief)) {
    process.exit(0);
  }
}

process.exit(1);
EOF
}

quality_load_classifier_metadata() {
    mapfile -t classifier_required_roles < <(printf '%s' "$classification_json" | node -e '
let input = "";
process.stdin.on("data", (chunk) => { input += chunk; });
process.stdin.on("end", () => {
  const document = JSON.parse(input || "{}");
  for (const role of document.required_roles || []) {
    process.stdout.write(String(role));
    process.stdout.write("\n");
  }
});
')
    mapfile -t classifier_optional_roles < <(printf '%s' "$classification_json" | node -e '
let input = "";
process.stdin.on("data", (chunk) => { input += chunk; });
process.stdin.on("end", () => {
  const document = JSON.parse(input || "{}");
  for (const role of document.optional_roles || []) {
    process.stdout.write(String(role));
    process.stdout.write("\n");
  }
});
')
    classification="$(read_classifier_field classification)"
    classification_rationale="$(read_classifier_field rationale)"
    verifier_profile="$(read_classifier_field verifier_profile)"
}

join_by_semicolon() {
    local first=1
    local item
    for item in "$@"; do
        [ -z "$item" ] && continue
        if [ "$first" -eq 1 ]; then
            printf '%s' "$item"
            first=0
        else
            printf '; %s' "$item"
        fi
    done
}

array_contains() {
    local needle="$1"
    shift
    local item
    for item in "$@"; do
        if [ "$item" = "$needle" ]; then
            return 0
        fi
    done
    return 1
}

is_truthy() {
    case "${1:-}" in
        1|true|TRUE|yes|YES|on|ON)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

quality_has_any_solidity_change() {
    [ "$has_src_sol" -eq 1 ] || [ "$has_script_sol" -eq 1 ] || [ "$has_sol_tests" -eq 1 ]
}

quality_print_solidity_context() {
    local label="$1"
    echo "[$label] change classification: $classification"
    echo "[$label] classification rationale: $classification_rationale"
    echo "[$label] default roles: $(join_by_semicolon "solidity-implementer" "${classifier_required_roles[@]}")"
    echo "[$label] optional roles: $(join_by_semicolon "${classifier_optional_roles[@]}")"
    echo "[$label] verifier profile: $verifier_profile"
}

quality_changed_files_have_declared_spec_surface() {
    local changed_files_file="$1"
    local task_brief_directory="$2"

    node - "$changed_files_file" "$task_brief_directory" <<'EOF'
const fs = require('fs');
const path = require('path');

const [, , changedFilesPath, taskBriefDirectory] = process.argv;
const changedFiles = fs.readFileSync(changedFilesPath, 'utf8').split(/\r?\n/).filter(Boolean);

function readIfExists(targetPath) {
  if (!targetPath || !fs.existsSync(targetPath)) return '';
  return fs.readFileSync(targetPath, 'utf8');
}

function extractField(document, field) {
  const prefix = `- ${field}:`;
  const lines = document.split(/\r?\n/);
  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index];
    if (!line.startsWith(prefix)) continue;

    let value = line.slice(prefix.length).trim();
    for (let cursor = index + 1; cursor < lines.length; cursor += 1) {
      const next = lines[cursor];
      if (/^- [^:]+:/.test(next)) break;
      if (next.startsWith('  ') || next === '') {
        value += `\n${next}`;
        continue;
      }
      break;
    }
    return value.trim();
  }
  return '';
}

function extractPathTokens(value) {
  const matches = value.match(/(?:^|[\s,;()[\]{}])((?:\/|(?:\.\.\/)+|\.\/)?[A-Za-z0-9._-]+(?:\/[A-Za-z0-9._-]+)+)(?=$|[\s,;()[\]{}:])/g) || [];
  return matches
    .map((entry) => entry.trim().replace(/^[\s,;()[\]{}]+/, '').replace(/[\s,;()[\]{}:]+$/, ''))
    .filter(Boolean);
}

function isTruthy(value) {
  return /^(yes|true|1)$/i.test(String(value || '').trim());
}

function isBrief(document) {
  return document.startsWith('# Task Brief') || document.startsWith('# Follow-up Brief');
}

function isSpecBrief(document) {
  return extractField(document, 'Artifact type').trim() === 'spec'
    || isTruthy(extractField(document, 'Spec review required'));
}

const changedSet = new Set(changedFiles);
const changedBriefs = changedFiles
  .map((file) => [file, readIfExists(file)])
  .filter(([, document]) => document && isBrief(document) && isSpecBrief(document));

if (changedBriefs.length > 0) {
  process.exit(0);
}

if (!taskBriefDirectory || !fs.existsSync(taskBriefDirectory)) {
  process.exit(1);
}

const historicalBriefs = fs
  .readdirSync(taskBriefDirectory)
  .filter((entry) => entry.endsWith('.md') && entry !== 'README.md' && entry !== 'TEMPLATE.md')
  .map((entry) => path.join(taskBriefDirectory, entry))
  .map((briefPath) => [briefPath, readIfExists(briefPath)])
  .filter(([, document]) => document && isBrief(document) && isSpecBrief(document));

for (const [, document] of historicalBriefs) {
  const specArtifactPaths = extractPathTokens(extractField(document, 'Spec artifact paths'));
  if (specArtifactPaths.some((artifactPath) => changedSet.has(artifactPath))) {
    process.exit(0);
  }
}

process.exit(1);
EOF
}

quality_prepare_standard_context() {
    quality_prepare_changed_files_tmp
    quality_prepare_workflow_changed_files_tmp

    src_sol_pattern="$(read_policy_value quality_gate.src_sol_pattern)"
    script_sol_pattern="$(read_policy_value quality_gate.script_sol_pattern '^script/.*\.sol$')"
    test_tsol_pattern="$(read_policy_value quality_gate.test_tsol_pattern)"
    test_sol_pattern="$(read_policy_value quality_gate.test_sol_pattern)"
    shell_pattern="$(read_policy_value quality_gate.shell_pattern)"
    process_surface_pattern="$(read_policy_value quality_gate.process_surface_pattern)"
    spec_surface_pattern="$(read_policy_value quality_gate.spec_surface_pattern '^(docs/spec/.*|docs/superpowers/specs/.*)$')"
    claude_spec_surface_pattern='^\.claude/(agents/spec-reviewer\.md|rules/spec-surface\.md)$'
    process_js_pattern="$(read_policy_value quality_gate.process_js_pattern)"
    package_pattern="$(read_policy_value quality_gate.package_pattern)"
    docs_contract_pattern="$(read_policy_value quality_gate.docs_contract_pattern)"
    task_brief_directory="$(read_policy_value agents.task_brief_directory 'docs/task-briefs')"
    agent_report_directory="$(read_policy_value agents.agent_report_directory 'docs/agent-reports')"
    mapfile -t process_selftest_patterns < <(read_policy_lines quality_gate.process_selftest_patterns)
    mapfile -t spec_default_roles < <(read_policy_lines quality_gate.spec_default_roles)
    mapfile -t process_default_roles < <(read_policy_lines quality_gate.process_default_roles)
    mapfile -t package_default_roles < <(read_policy_lines quality_gate.package_default_roles)
    mapfile -t docs_contract_default_roles < <(read_policy_lines quality_gate.docs_contract_default_roles)
    task_brief_directory="$(read_policy_value agents.task_brief_directory 'docs/task-briefs')"

    classification_json="$(
        QUALITY_GATE_MODE="$mode" \
        QUALITY_GATE_FILE_LIST="$workflow_changed_files_tmp" \
        CHANGE_CLASSIFIER_FORCE="${CHANGE_CLASSIFIER_FORCE:-}" \
        CHANGE_CLASSIFIER_DIFF_FILE="${CHANGE_CLASSIFIER_DIFF_FILE:-}" \
        node ./script/process/classify-change.js
    )"
    quality_load_classifier_metadata

    has_src_sol=0
    has_script_sol=0
    has_sol_tests=0
    has_package_metadata=0
    has_docs_contract=0
    has_process_surface=0
    has_spec_surface=0
    should_run_docs_check=0
    should_run_process_selftest=0
    workflow_has_src_sol=0
    workflow_has_script_sol=0
    src_solidity_candidates=()
    script_solidity_candidates=()
    test_solidity_candidates=()
    solidity_files=()
    src_solidity_files=()
    workflow_src_solidity_files=()
    workflow_script_solidity_files=()
    changed_test_files=()
    shell_candidates=()
    shell_files=()
    process_js_candidates=()
    process_js_files=()

    while IFS= read -r file; do
        [ -z "$file" ] && continue

        if [[ "$file" =~ $src_sol_pattern ]]; then
            has_src_sol=1
            src_solidity_candidates+=("$file")
        elif [[ "$file" =~ $script_sol_pattern ]]; then
            has_script_sol=1
            script_solidity_candidates+=("$file")
        elif [[ "$file" =~ $test_tsol_pattern ]]; then
            has_sol_tests=1
            test_solidity_candidates+=("$file")
            changed_test_files+=("$file")
        elif [[ "$file" =~ $test_sol_pattern ]]; then
            has_sol_tests=1
            test_solidity_candidates+=("$file")
        fi

        if [[ "$file" =~ $process_surface_pattern ]]; then
            has_process_surface=1
            should_run_docs_check=1
        fi

        if [[ "$file" =~ $spec_surface_pattern ]]; then
            has_spec_surface=1
            should_run_docs_check=1
            should_run_process_selftest=1
        fi

        if [[ "$file" =~ $claude_spec_surface_pattern ]]; then
            has_process_surface=1
            should_run_docs_check=1
            should_run_process_selftest=1
        fi

        if quality_file_declares_spec_surface "$file"; then
            has_spec_surface=1
            should_run_docs_check=1
            should_run_process_selftest=1
        fi

        if [[ "$file" =~ $shell_pattern ]]; then
            has_process_surface=1
            should_run_docs_check=1
            shell_candidates+=("$file")
        fi

        if [[ "$file" =~ $process_js_pattern ]]; then
            has_process_surface=1
            should_run_docs_check=1
            process_js_candidates+=("$file")
        fi

        if [[ "$file" =~ $package_pattern ]]; then
            has_package_metadata=1
            should_run_docs_check=1
        fi

        if [[ "$file" =~ $docs_contract_pattern ]]; then
            has_docs_contract=1
            should_run_docs_check=1
        fi

        for pattern in "${process_selftest_patterns[@]}"; do
            if [[ "$file" =~ $pattern ]]; then
                should_run_process_selftest=1
                break
            fi
        done
    done <<< "$changed_files"

    if quality_changed_files_have_declared_spec_surface "$changed_files_tmp" "$task_brief_directory"; then
        has_spec_surface=1
        should_run_docs_check=1
        should_run_process_selftest=1
    fi

    while IFS= read -r file; do
        [ -z "$file" ] && continue

        if [[ "$file" =~ $src_sol_pattern ]]; then
            workflow_has_src_sol=1
            if [ -f "$file" ]; then
                workflow_src_solidity_files+=("$file")
            fi
        elif [[ "$file" =~ $script_sol_pattern ]]; then
            workflow_has_script_sol=1
            if [ -f "$file" ]; then
                workflow_script_solidity_files+=("$file")
            fi
        fi
    done <<< "$workflow_changed_files"

    for file in "${src_solidity_candidates[@]}" "${script_solidity_candidates[@]}" "${test_solidity_candidates[@]}"; do
        [ -z "$file" ] && continue
        if [ -f "$file" ]; then
            solidity_files+=("$file")
        fi
    done

    for file in "${src_solidity_candidates[@]}"; do
        [ -z "$file" ] && continue
        if [ -f "$file" ]; then
            src_solidity_files+=("$file")
        fi
    done

    for file in "${shell_candidates[@]}"; do
        [ -z "$file" ] && continue
        if [ -f "$file" ]; then
            shell_files+=("$file")
        fi
    done

    for file in "${process_js_candidates[@]}"; do
        [ -z "$file" ] && continue
        if [ -f "$file" ]; then
            process_js_files+=("$file")
        fi
    done
}

quality_prepare_standard_gate_context() {
    quality_prepare_standard_context

    stale_evidence_remediation_command="$(read_policy_value quality_gate.stale_evidence_remediation_command 'npm run stale-evidence:loop')"
    stale_evidence_exit_code="$(read_policy_value quality_gate.stale_evidence_exit_code '2')"
    mapfile -t local_codex_review_classifications < <(read_policy_lines_or_default verifier.local_codex_review.required_classifications 'prod-semantic' 'high-risk')
    local_codex_review_force_env="$(read_policy_value verifier.local_codex_review.force_env 'FORCE_CODEX_REVIEW')"
}
