#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

mode="${QUALITY_GATE_MODE:-staged}"

read_policy_value() {
    local key="$1"
    local default_value="$2"
    local value

    if value="$(node ./script/process/read-process-config.js policy "$key" 2>/dev/null)"; then
        printf '%s' "$value"
        return
    fi

    printf '%s' "$default_value"
}

load_changed_files_from_ci() {
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

load_changed_files() {
    if [ "$mode" = "ci" ]; then
        load_changed_files_from_ci
        return
    fi

    git diff --cached --name-only --diff-filter=ACMRD
}

discover_review_note() {
    local changed_files_file="$1"
    shift
    local candidates=("$@")

    if [ "${#candidates[@]}" -eq 0 ]; then
        return 1
    fi

    node - "$changed_files_file" "${candidates[@]}" <<'EOF'
const fs = require('fs');

const [, , changedFilesPath, ...candidates] = process.argv;
const changedFiles = fs.readFileSync(changedFilesPath, 'utf8').split(/\r?\n/).filter(Boolean);
const changedSolidityFiles = changedFiles.filter((file) => /^(src|script|test)\/.*\.sol$/.test(file));
const changedProductionSolidityFiles = changedFiles.filter((file) => /^(src|script)\/.*\.sol$/.test(file));
const targetSolidityFiles = changedProductionSolidityFiles.length > 0 ? changedProductionSolidityFiles : changedSolidityFiles;

function extractField(document, field) {
  const prefix = `- ${field}:`;
  for (const line of document.split(/\r?\n/)) {
    if (line.startsWith(prefix)) {
      return line.slice(prefix.length).trim();
    }
  }
  return '';
}

function extractPathTokens(value) {
  const matches = value.match(/(?:^|[\s,;()[\]{}])((?:\/|(?:\.\.\/)+|\.\/)?[A-Za-z0-9._-]+(?:\/[A-Za-z0-9._-]+)+)(?=$|[\s,;()[\]{}:])/g) || [];
  return matches
    .map((entry) => entry.trim().replace(/^[\s,;()[\]{}]+/, '').replace(/[\s,;()[\]{}:]+$/, ''))
    .filter(Boolean);
}

const matching = candidates.filter((candidate) => {
  const document = fs.readFileSync(candidate, 'utf8');
  const filesReviewed = extractField(document, 'Files reviewed');
  const reviewedTokens = new Set(extractPathTokens(filesReviewed));
  return targetSolidityFiles.some((changedFile) => reviewedTokens.has(changedFile));
});

if (matching.length === 1) {
  process.stdout.write(matching[0]);
  process.exit(0);
}

if (matching.length === 0) {
  console.error(
    '[check-solidity-review-note] ERROR: review note discovery found no candidate whose Files reviewed field references the changed Solidity paths. Set QUALITY_GATE_REVIEW_NOTE explicitly.'
      .replace('changed Solidity paths', changedProductionSolidityFiles.length > 0 ? 'changed production Solidity paths' : 'changed Solidity paths')
  );
  process.exit(2);
}

console.error(
  `[check-solidity-review-note] ERROR: review note discovery matched multiple candidates (${matching.join(', ')}). Set QUALITY_GATE_REVIEW_NOTE explicitly.`
);
process.exit(2);
EOF
}

changed_files="$(load_changed_files)"

if [ -z "$changed_files" ]; then
    exit 0
fi

if ! printf '%s\n' "$changed_files" | grep -Eq '^(src|test|script)/.*\.sol$'; then
    exit 0
fi

changed_files_tmp="$(mktemp)"
trap 'rm -f "$changed_files_tmp"' EXIT
printf '%s\n' "$changed_files" > "$changed_files_tmp"
classification_json="$(QUALITY_GATE_MODE="$mode" QUALITY_GATE_FILE_LIST="$changed_files_tmp" CHANGE_CLASSIFIER_DIFF_FILE="${CHANGE_CLASSIFIER_DIFF_FILE:-}" node ./script/process/classify-change.js)"

review_note="${QUALITY_GATE_REVIEW_NOTE:-}"
if [ -z "$review_note" ]; then
    review_dir="$(read_policy_value quality_gate.review_note_directory 'docs/reviews')"

    if [ ! -d "$review_dir" ]; then
        echo "[check-solidity-review-note] ERROR: review note not found. Set QUALITY_GATE_REVIEW_NOTE or add one under the configured review note directory."
        exit 1
    fi

    mapfile -t review_candidates < <(find "$review_dir" -maxdepth 1 -type f -name '*.md' ! -name 'README.md' ! -name 'TEMPLATE.md' | sort)
    review_note="$(discover_review_note "$changed_files_tmp" "${review_candidates[@]}" || true)"
fi

if [ -z "$review_note" ] || [ ! -f "$review_note" ]; then
    echo "[check-solidity-review-note] ERROR: review note not found. Set QUALITY_GATE_REVIEW_NOTE or add one under the configured review note directory."
    exit 1
fi

bash ./script/process/check-review-note.sh "$review_note"

field_owners_json="$(read_policy_value review_note.field_owners '{}')"
owner_prefixed_fields_json="$(read_policy_value review_note.owner_prefixed_source_fields '[]')"
solidity_required_fields_json="$(read_policy_value solidity_review_note.required_fields '[]')"
solidity_boolean_fields_json="$(read_policy_value solidity_review_note.boolean_fields '[]')"
freshness_source_fields_json="$(read_policy_value solidity_review_note.freshness_source_fields '["Logic evidence source","Security evidence source","Gas evidence source","Verification evidence source"]')"
review_note_must_postdate_agent_report="$(read_policy_value solidity_review_note.review_note_must_postdate_agent_report 'true')"
agent_report_must_postdate_changed_files="$(read_policy_value solidity_review_note.agent_report_must_postdate_changed_files 'true')"
task_brief_required_fields_json="$(read_policy_value task_brief.required_fields '[]')"
task_brief_boolean_fields_json="$(read_policy_value task_brief.boolean_fields '[]')"
agent_report_required_fields_json="$(read_policy_value agent_report.required_fields '[]')"
agent_report_boolean_fields_json="$(read_policy_value agent_report.boolean_fields '[]')"
task_brief_field="$(read_policy_value solidity_review_note.task_brief_field 'Task Brief path')"
agent_report_field="$(read_policy_value solidity_review_note.agent_report_field 'Agent Report path')"
implementation_owner_field="$(read_policy_value solidity_review_note.implementation_owner_field 'Implementation owner')"
writer_dispatch_confirmed_field="$(read_policy_value solidity_review_note.writer_dispatch_confirmed_field 'Writer dispatch confirmed')"
semantic_dimensions_field="$(read_policy_value solidity_review_note.semantic_dimensions_field 'Semantic dimensions reviewed')"
source_of_truth_field="$(read_policy_value solidity_review_note.source_of_truth_field 'Source-of-truth docs checked')"
external_facts_field="$(read_policy_value solidity_review_note.external_facts_field 'External facts checked')"
local_control_flow_field="$(read_policy_value solidity_review_note.local_control_flow_field 'Local control-flow facts checked')"
evidence_chain_field="$(read_policy_value solidity_review_note.evidence_chain_field 'Evidence chain complete')"
semantic_alignment_summary_field="$(read_policy_value solidity_review_note.semantic_alignment_summary_field 'Semantic alignment summary')"
critical_assumptions_field="$(read_policy_value solidity_review_note.critical_assumptions_field "$semantic_alignment_summary_field")"
task_brief_semantic_dimensions_field="$(read_policy_value solidity_review_note.task_brief_semantic_dimensions_field 'Semantic review dimensions')"
task_brief_source_of_truth_field="$(read_policy_value solidity_review_note.task_brief_source_of_truth_field 'Source-of-truth docs')"
task_brief_external_sources_field="$(read_policy_value solidity_review_note.task_brief_external_sources_field 'External sources required')"
task_brief_critical_assumptions_field="$(read_policy_value solidity_review_note.task_brief_critical_assumptions_field 'Critical assumptions to prove or reject')"
task_brief_files_in_scope_field="$(read_policy_value solidity_review_note.task_brief_files_in_scope_field 'Files in scope')"
task_brief_default_writer_role_field="$(read_policy_value solidity_review_note.task_brief_default_writer_role_field 'Default writer role')"
task_brief_implementation_owner_field="$(read_policy_value solidity_review_note.task_brief_implementation_owner_field 'Implementation owner')"
task_brief_write_permissions_field="$(read_policy_value solidity_review_note.task_brief_write_permissions_field 'Write permissions')"
task_brief_required_roles_field="$(read_policy_value task_brief.required_roles_field 'Required roles')"
task_brief_required_verifier_commands_field="$(read_policy_value task_brief.required_verifier_commands_field 'Required verifier commands')"
task_brief_review_note_required_field="$(read_policy_value task_brief.review_note_required_field 'Review note required')"
task_brief_dispatch_backend_field="$(read_policy_value task_brief.dispatch_backend_field 'Writer dispatch backend')"
task_brief_dispatch_target_field="$(read_policy_value task_brief.dispatch_target_field 'Writer dispatch target')"
task_brief_change_classification_field="$(read_policy_value task_brief.change_classification_field 'Change classification')"
task_brief_verifier_profile_field="$(read_policy_value task_brief.verifier_profile_field 'Verifier profile')"
semantic_sensitive_patterns_json="$(read_policy_value solidity_review_note.semantic_sensitive_patterns '[]')"
required_writer_patterns_json="$(read_policy_value agents.required_writer_for_patterns '{}')"
src_default_roles_json="$(read_policy_value quality_gate.src_default_roles '[]')"
test_default_roles_json="$(read_policy_value quality_gate.test_default_roles '[]')"
task_brief_directory="$(read_policy_value agents.task_brief_directory 'docs/task-briefs')"
agent_report_directory="$(read_policy_value agents.agent_report_directory 'docs/agent-reports')"
main_session_role="$(read_policy_value agents.main_session_role 'main-orchestrator')"
main_session_forbidden_patterns_json="$(read_policy_value agents.main_session_forbidden_write_patterns '[]')"
agent_report_task_brief_field="$(read_policy_value agent_report.task_brief_field 'Task Brief path')"
agent_report_scope_respected_field="$(read_policy_value agent_report.scope_respected_field 'Scope / ownership respected')"
agent_report_role_field="$(read_policy_value agent_report.role_field 'Role')"
agent_report_files_field="$(read_policy_value agent_report.files_field 'Files touched/reviewed')"
codex_review_summary_field="$(read_policy_value solidity_review_note.codex_review_summary_field 'Codex review summary')"
codex_review_evidence_field="$(read_policy_value solidity_review_note.codex_review_evidence_field 'Codex review evidence source')"
codex_review_task_brief_token="$(read_policy_value verifier.codex_review.task_brief_token 'npm run codex:review')"
codex_review_command_tokens_json="$(read_policy_value verifier.codex_review.command_tokens '["npm run codex:review","bash ./script/process/run-codex-review.sh","codex review --uncommitted","codex review"]')"
codex_local_required_classifications_json="$(read_policy_value verifier.local_codex_review.required_classifications '["prod-semantic","high-risk"]')"
codex_local_force_env="$(read_policy_value verifier.local_codex_review.force_env 'FORCE_CODEX_REVIEW')"

REVIEW_FIELD_OWNERS="$field_owners_json" \
REVIEW_OWNER_PREFIXED_FIELDS="$owner_prefixed_fields_json" \
SOLIDITY_REQUIRED_FIELDS="$solidity_required_fields_json" \
SOLIDITY_BOOLEAN_FIELDS="$solidity_boolean_fields_json" \
FRESHNESS_SOURCE_FIELDS="$freshness_source_fields_json" \
REVIEW_NOTE_MUST_POSTDATE_AGENT_REPORT="$review_note_must_postdate_agent_report" \
AGENT_REPORT_MUST_POSTDATE_CHANGED_FILES="$agent_report_must_postdate_changed_files" \
TASK_BRIEF_REQUIRED_FIELDS="$task_brief_required_fields_json" \
TASK_BRIEF_BOOLEAN_FIELDS="$task_brief_boolean_fields_json" \
AGENT_REPORT_REQUIRED_FIELDS="$agent_report_required_fields_json" \
AGENT_REPORT_BOOLEAN_FIELDS="$agent_report_boolean_fields_json" \
TASK_BRIEF_FIELD="$task_brief_field" \
AGENT_REPORT_FIELD="$agent_report_field" \
IMPLEMENTATION_OWNER_FIELD="$implementation_owner_field" \
WRITER_DISPATCH_CONFIRMED_FIELD="$writer_dispatch_confirmed_field" \
SEMANTIC_DIMENSIONS_FIELD="$semantic_dimensions_field" \
SOURCE_OF_TRUTH_FIELD="$source_of_truth_field" \
EXTERNAL_FACTS_FIELD="$external_facts_field" \
LOCAL_CONTROL_FLOW_FIELD="$local_control_flow_field" \
EVIDENCE_CHAIN_FIELD="$evidence_chain_field" \
SEMANTIC_ALIGNMENT_SUMMARY_FIELD="$semantic_alignment_summary_field" \
CRITICAL_ASSUMPTIONS_FIELD="$critical_assumptions_field" \
TASK_BRIEF_SEMANTIC_DIMENSIONS_FIELD="$task_brief_semantic_dimensions_field" \
TASK_BRIEF_SOURCE_OF_TRUTH_FIELD="$task_brief_source_of_truth_field" \
TASK_BRIEF_EXTERNAL_SOURCES_FIELD="$task_brief_external_sources_field" \
TASK_BRIEF_CRITICAL_ASSUMPTIONS_FIELD="$task_brief_critical_assumptions_field" \
TASK_BRIEF_FILES_IN_SCOPE_FIELD="$task_brief_files_in_scope_field" \
TASK_BRIEF_DEFAULT_WRITER_ROLE_FIELD="$task_brief_default_writer_role_field" \
TASK_BRIEF_IMPLEMENTATION_OWNER_FIELD="$task_brief_implementation_owner_field" \
TASK_BRIEF_WRITE_PERMISSIONS_FIELD="$task_brief_write_permissions_field" \
TASK_BRIEF_REQUIRED_ROLES_FIELD="$task_brief_required_roles_field" \
TASK_BRIEF_REQUIRED_VERIFIER_COMMANDS_FIELD="$task_brief_required_verifier_commands_field" \
TASK_BRIEF_REVIEW_NOTE_REQUIRED_FIELD="$task_brief_review_note_required_field" \
TASK_BRIEF_DISPATCH_BACKEND_FIELD="$task_brief_dispatch_backend_field" \
TASK_BRIEF_DISPATCH_TARGET_FIELD="$task_brief_dispatch_target_field" \
AGENT_REPORT_TASK_BRIEF_FIELD="$agent_report_task_brief_field" \
AGENT_REPORT_SCOPE_RESPECTED_FIELD="$agent_report_scope_respected_field" \
AGENT_REPORT_ROLE_FIELD="$agent_report_role_field" \
AGENT_REPORT_FILES_FIELD="$agent_report_files_field" \
CODEX_REVIEW_SUMMARY_FIELD="$codex_review_summary_field" \
CODEX_REVIEW_EVIDENCE_FIELD="$codex_review_evidence_field" \
CODEX_REVIEW_TASK_BRIEF_TOKEN="$codex_review_task_brief_token" \
CODEX_REVIEW_COMMAND_TOKENS="$codex_review_command_tokens_json" \
CODEX_LOCAL_REQUIRED_CLASSIFICATIONS="$codex_local_required_classifications_json" \
CODEX_LOCAL_FORCE_ENV="$codex_local_force_env" \
CLASSIFICATION_RESULT="$classification_json" \
TASK_BRIEF_CHANGE_CLASSIFICATION_FIELD="$task_brief_change_classification_field" \
TASK_BRIEF_VERIFIER_PROFILE_FIELD="$task_brief_verifier_profile_field" \
SRC_DEFAULT_ROLES="$src_default_roles_json" \
TEST_DEFAULT_ROLES="$test_default_roles_json" \
SEMANTIC_SENSITIVE_PATTERNS="$semantic_sensitive_patterns_json" \
REQUIRED_WRITER_PATTERNS="$required_writer_patterns_json" \
TASK_BRIEF_DIRECTORY="$task_brief_directory" \
AGENT_REPORT_DIRECTORY="$agent_report_directory" \
MAIN_SESSION_ROLE="$main_session_role" \
MAIN_SESSION_FORBIDDEN_PATTERNS="$main_session_forbidden_patterns_json" \
node - "$review_note" "$changed_files_tmp" <<'EOF'
const fs = require('fs');
const path = require('path');

const [, , reviewNotePath, changedFilesPath] = process.argv;
const reviewNote = fs.readFileSync(reviewNotePath, 'utf8');
const changedFiles = fs.readFileSync(changedFilesPath, 'utf8').split(/\r?\n/).filter(Boolean);
const changedSolidityFiles = changedFiles.filter((file) => /^(src|script|test)\/.*\.sol$/.test(file));
const changedProductionSolidityFiles = changedFiles.filter((file) => /^(src|script)\/.*\.sol$/.test(file));
const targetSolidityFiles = changedProductionSolidityFiles.length > 0 ? changedProductionSolidityFiles : changedSolidityFiles;
const reviewFieldOwners = JSON.parse(process.env.REVIEW_FIELD_OWNERS || '{}');
const ownerPrefixedFields = JSON.parse(process.env.REVIEW_OWNER_PREFIXED_FIELDS || '[]');
const solidityRequiredFields = JSON.parse(process.env.SOLIDITY_REQUIRED_FIELDS || '[]');
const solidityBooleanFields = JSON.parse(process.env.SOLIDITY_BOOLEAN_FIELDS || '[]');
const freshnessSourceFields = JSON.parse(process.env.FRESHNESS_SOURCE_FIELDS || '[]');
const taskBriefRequiredFields = JSON.parse(process.env.TASK_BRIEF_REQUIRED_FIELDS || '[]');
const taskBriefBooleanFields = JSON.parse(process.env.TASK_BRIEF_BOOLEAN_FIELDS || '[]');
const agentReportRequiredFields = JSON.parse(process.env.AGENT_REPORT_REQUIRED_FIELDS || '[]');
const agentReportBooleanFields = JSON.parse(process.env.AGENT_REPORT_BOOLEAN_FIELDS || '[]');
const semanticSensitivePatterns = JSON.parse(process.env.SEMANTIC_SENSITIVE_PATTERNS || '[]');
const requiredWriterPatterns = JSON.parse(process.env.REQUIRED_WRITER_PATTERNS || '{}');
const srcDefaultRoles = JSON.parse(process.env.SRC_DEFAULT_ROLES || '[]');
const testDefaultRoles = JSON.parse(process.env.TEST_DEFAULT_ROLES || '[]');
const codexReviewCommandTokens = JSON.parse(process.env.CODEX_REVIEW_COMMAND_TOKENS || '[]');
const classificationResult = JSON.parse(process.env.CLASSIFICATION_RESULT || '{}');
const reviewNoteMustPostdateAgentReport = /^(1|true|yes)$/i.test(process.env.REVIEW_NOTE_MUST_POSTDATE_AGENT_REPORT || 'true');
const agentReportMustPostdateChangedFiles = /^(1|true|yes)$/i.test(process.env.AGENT_REPORT_MUST_POSTDATE_CHANGED_FILES || 'true');

const configuredTaskBriefDirectory = process.env.TASK_BRIEF_DIRECTORY || 'docs/task-briefs';
const configuredAgentReportDirectory = process.env.AGENT_REPORT_DIRECTORY || 'docs/agent-reports';
const mainSessionRole = process.env.MAIN_SESSION_ROLE || 'main-orchestrator';
const mainSessionForbiddenPatterns = JSON.parse(process.env.MAIN_SESSION_FORBIDDEN_PATTERNS || '[]');
const taskBriefField = process.env.TASK_BRIEF_FIELD || 'Task Brief path';
const agentReportField = process.env.AGENT_REPORT_FIELD || 'Agent Report path';
const implementationOwnerField = process.env.IMPLEMENTATION_OWNER_FIELD || 'Implementation owner';
const writerDispatchConfirmedField = process.env.WRITER_DISPATCH_CONFIRMED_FIELD || 'Writer dispatch confirmed';
const semanticDimensionsField = process.env.SEMANTIC_DIMENSIONS_FIELD || 'Semantic dimensions reviewed';
const sourceOfTruthField = process.env.SOURCE_OF_TRUTH_FIELD || 'Source-of-truth docs checked';
const externalFactsField = process.env.EXTERNAL_FACTS_FIELD || 'External facts checked';
const localControlFlowField = process.env.LOCAL_CONTROL_FLOW_FIELD || 'Local control-flow facts checked';
const evidenceChainField = process.env.EVIDENCE_CHAIN_FIELD || 'Evidence chain complete';
const semanticAlignmentSummaryField = process.env.SEMANTIC_ALIGNMENT_SUMMARY_FIELD || 'Semantic alignment summary';
const criticalAssumptionsField = process.env.CRITICAL_ASSUMPTIONS_FIELD || semanticAlignmentSummaryField;
const taskBriefSemanticDimensionsField = process.env.TASK_BRIEF_SEMANTIC_DIMENSIONS_FIELD || 'Semantic review dimensions';
const taskBriefSourceOfTruthField = process.env.TASK_BRIEF_SOURCE_OF_TRUTH_FIELD || 'Source-of-truth docs';
const taskBriefExternalSourcesField = process.env.TASK_BRIEF_EXTERNAL_SOURCES_FIELD || 'External sources required';
const taskBriefCriticalAssumptionsField = process.env.TASK_BRIEF_CRITICAL_ASSUMPTIONS_FIELD || 'Critical assumptions to prove or reject';
const taskBriefFilesInScopeField = process.env.TASK_BRIEF_FILES_IN_SCOPE_FIELD || 'Files in scope';
const taskBriefDefaultWriterRoleField = process.env.TASK_BRIEF_DEFAULT_WRITER_ROLE_FIELD || 'Default writer role';
const taskBriefImplementationOwnerField = process.env.TASK_BRIEF_IMPLEMENTATION_OWNER_FIELD || 'Implementation owner';
const taskBriefWritePermissionsField = process.env.TASK_BRIEF_WRITE_PERMISSIONS_FIELD || 'Write permissions';
const taskBriefRequiredRolesField = process.env.TASK_BRIEF_REQUIRED_ROLES_FIELD || 'Required roles';
const taskBriefRequiredVerifierCommandsField = process.env.TASK_BRIEF_REQUIRED_VERIFIER_COMMANDS_FIELD || 'Required verifier commands';
const taskBriefReviewNoteRequiredField = process.env.TASK_BRIEF_REVIEW_NOTE_REQUIRED_FIELD || 'Review note required';
const taskBriefDispatchBackendField = process.env.TASK_BRIEF_DISPATCH_BACKEND_FIELD || 'Writer dispatch backend';
const taskBriefDispatchTargetField = process.env.TASK_BRIEF_DISPATCH_TARGET_FIELD || 'Writer dispatch target';
const taskBriefChangeClassificationField = process.env.TASK_BRIEF_CHANGE_CLASSIFICATION_FIELD || 'Change classification';
const taskBriefVerifierProfileField = process.env.TASK_BRIEF_VERIFIER_PROFILE_FIELD || 'Verifier profile';
const agentReportTaskBriefField = process.env.AGENT_REPORT_TASK_BRIEF_FIELD || 'Task Brief path';
const agentReportScopeRespectedField = process.env.AGENT_REPORT_SCOPE_RESPECTED_FIELD || 'Scope / ownership respected';
const agentReportRoleField = process.env.AGENT_REPORT_ROLE_FIELD || 'Role';
const agentReportFilesField = process.env.AGENT_REPORT_FILES_FIELD || 'Files touched/reviewed';
const codexReviewSummaryField = process.env.CODEX_REVIEW_SUMMARY_FIELD || 'Codex review summary';
const codexReviewEvidenceField = process.env.CODEX_REVIEW_EVIDENCE_FIELD || 'Codex review evidence source';
const codexReviewTaskBriefToken = process.env.CODEX_REVIEW_TASK_BRIEF_TOKEN || 'npm run codex:review';
const codexLocalRequiredClassifications = JSON.parse(process.env.CODEX_LOCAL_REQUIRED_CLASSIFICATIONS || '["prod-semantic","high-risk"]');
const codexLocalForceEnv = process.env.CODEX_LOCAL_FORCE_ENV || 'FORCE_CODEX_REVIEW';
const classifierRequiredRoles = Array.isArray(classificationResult.required_roles) ? classificationResult.required_roles : [];
const classifierClassification = classificationResult.classification || 'none';
const classifierVerifierProfile = classificationResult.verifier_profile || 'none';
const requiredFreshnessFields = freshnessSourceFields.filter((field) => {
  if (field === 'Verification evidence source') return true;
  if (field === 'Logic evidence source') return classifierRequiredRoles.includes('logic-reviewer');
  if (field === 'Security evidence source') return classifierRequiredRoles.includes('security-reviewer');
  if (field === 'Gas evidence source') return classifierRequiredRoles.includes('gas-reviewer');
  return false;
});

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

function isNoneLike(value) {
  return /^(none|n\/a|na|not applicable)$/i.test(String(value).trim());
}

function tokenizeField(value) {
  if (String(value).trim() === '' || isNoneLike(value)) return [];
  return String(value)
    .split(/[;,]/)
    .map((entry) => entry.trim())
    .filter(Boolean);
}

function isTruthy(value) {
  return /^(1|true|yes|on)$/i.test(String(value || '').trim());
}

function ensureTokensPresent(fieldName, expectedTokens, actualValue, sourceLabel, failures) {
  const normalizedActual = String(actualValue).toLowerCase();
  for (const token of expectedTokens) {
    if (!normalizedActual.includes(String(token).toLowerCase())) {
      failures.push(`${fieldName}: must mention '${token}' from ${sourceLabel}.`);
    }
  }
}

function ensureAnyTokenPresent(fieldName, expectedTokens, actualValue, sourceLabel, failures) {
  if (!Array.isArray(expectedTokens) || expectedTokens.length === 0) return;
  const normalizedActual = String(actualValue).toLowerCase();
  if (!expectedTokens.some((token) => normalizedActual.includes(String(token).toLowerCase()))) {
    failures.push(`${fieldName}: must mention one of ${expectedTokens.join(', ')} from ${sourceLabel}.`);
  }
}

function fail(message) {
  failures.push(message);
}

if (!Array.isArray(ownerPrefixedFields)) {
  throw new Error('review_note.owner_prefixed_source_fields must be an array');
}

if (!Array.isArray(solidityRequiredFields) || !Array.isArray(solidityBooleanFields)) {
  throw new Error('solidity_review_note.required_fields and boolean_fields must be arrays');
}

if (!Array.isArray(taskBriefRequiredFields) || !Array.isArray(taskBriefBooleanFields)) {
  throw new Error('task_brief.required_fields and boolean_fields must be arrays');
}

if (!Array.isArray(agentReportRequiredFields) || !Array.isArray(agentReportBooleanFields)) {
  throw new Error('agent_report.required_fields and boolean_fields must be arrays');
}

if (!Array.isArray(freshnessSourceFields)) {
  throw new Error('solidity_review_note.freshness_source_fields must be an array');
}

const failures = [];
const requiresTaskBrief = solidityRequiredFields.includes(taskBriefField);
const requiresAgentReport = solidityRequiredFields.includes(agentReportField);
const codexReviewFields = new Set([codexReviewSummaryField, codexReviewEvidenceField]);
const requiredSolidityFields = solidityRequiredFields.filter((field) => !codexReviewFields.has(field));
const localCodexReviewRequired =
  Array.isArray(codexLocalRequiredClassifications) && codexLocalRequiredClassifications.includes(classifierClassification) ||
  isTruthy(process.env[codexLocalForceEnv]);

for (const field of ownerPrefixedFields) {
  if (typeof field !== 'string' || field.trim() === '') {
    throw new Error('review_note.owner_prefixed_source_fields entries must be non-empty strings');
  }
  const allowedOwner = reviewFieldOwners[field];
  if (allowedOwner !== undefined && typeof allowedOwner !== 'string') {
    throw new Error(`review_note.field_owners['${field}'] must be a string`);
  }
}

for (const field of requiredSolidityFields) {
  const value = extractField(reviewNote, field).trim();
  if (value === '') {
    fail(`${field}: missing required Solidity review-note field.`);
    continue;
  }
  if (solidityBooleanFields.includes(field) && value !== 'yes' && value !== 'no') {
    fail(`${field}: must be 'yes' or 'no'.`);
  }
}

const reviewFilesValue = extractField(reviewNote, 'Files reviewed').trim();
const reviewFileTokens = new Set(extractPathTokens(reviewFilesValue));
if (!targetSolidityFiles.some((changedFile) => reviewFileTokens.has(changedFile))) {
  fail(`Files reviewed: review note does not reference any changed ${changedProductionSolidityFiles.length > 0 ? 'production Solidity' : 'Solidity'} path.`);
}

const taskBriefPath = extractField(reviewNote, taskBriefField).trim();
let taskBrief = '';
if (taskBriefPath === '' && requiresTaskBrief) {
  fail(`${taskBriefField}: missing path.`);
} else if (taskBriefPath !== '') {
  const resolvedTaskBriefPath = path.resolve(taskBriefPath);
  const resolvedTaskBriefDirectory = path.resolve(configuredTaskBriefDirectory);
  if (!fs.existsSync(resolvedTaskBriefPath)) {
    fail(`${taskBriefField}: '${taskBriefPath}' does not exist.`);
  } else if (!(resolvedTaskBriefPath === resolvedTaskBriefDirectory || resolvedTaskBriefPath.startsWith(`${resolvedTaskBriefDirectory}${path.sep}`))) {
    fail(`${taskBriefField}: '${taskBriefPath}' must live under the configured task-brief directory '${configuredTaskBriefDirectory}'.`);
  } else {
    taskBrief = fs.readFileSync(resolvedTaskBriefPath, 'utf8');
  }
}

const implementationOwner = extractField(reviewNote, implementationOwnerField).trim();
const agentReportPath = extractField(reviewNote, agentReportField).trim();
let agentReport = '';
let agentReportMtimeMs = null;
if (agentReportPath === '' && requiresAgentReport) {
  fail(`${agentReportField}: missing path.`);
} else if (agentReportPath !== '') {
  const resolvedAgentReportPath = path.resolve(agentReportPath);
  const resolvedAgentReportDirectory = path.resolve(configuredAgentReportDirectory);
  if (!fs.existsSync(resolvedAgentReportPath)) {
    fail(`${agentReportField}: '${agentReportPath}' does not exist.`);
  } else if (!(resolvedAgentReportPath === resolvedAgentReportDirectory || resolvedAgentReportPath.startsWith(`${resolvedAgentReportDirectory}${path.sep}`))) {
    fail(`${agentReportField}: '${agentReportPath}' must live under the configured agent-report directory '${configuredAgentReportDirectory}'.`);
  } else {
    agentReport = fs.readFileSync(resolvedAgentReportPath, 'utf8');
    agentReportMtimeMs = fs.statSync(resolvedAgentReportPath).mtimeMs;
  }
}

if (agentReport !== '') {
  for (const field of agentReportRequiredFields) {
    const value = extractField(agentReport, field).trim();
    if (value === '') {
      fail(`${agentReportField}: missing agent report field '${field}'.`);
      continue;
    }
    if (agentReportBooleanFields.includes(field) && value !== 'yes' && value !== 'no') {
      fail(`${agentReportField}: field '${field}' must be 'yes' or 'no'.`);
    }
  }

  const agentReportRole = extractField(agentReport, agentReportRoleField).trim();
  const agentReportFiles = extractField(agentReport, agentReportFilesField).trim();
  const agentReportTaskBriefPath = extractField(agentReport, agentReportTaskBriefField).trim();
  const agentReportScopeRespected = extractField(agentReport, agentReportScopeRespectedField).trim();
  const agentReportFileTokens = new Set(extractPathTokens(agentReportFiles));

  if (agentReportRole === '') {
    fail(`${agentReportField}: missing '- ${agentReportRoleField}:' in agent report.`);
  } else if (implementationOwner !== '' && agentReportRole !== implementationOwner) {
    fail(`${agentReportField}: agent report role '${agentReportRole}' does not match ${implementationOwnerField} '${implementationOwner}'.`);
  }

  if (agentReportTaskBriefPath !== '' && taskBriefPath !== '' && path.resolve(agentReportTaskBriefPath) !== path.resolve(taskBriefPath)) {
    fail(`${agentReportField}: agent report ${agentReportTaskBriefField} must match review note ${taskBriefField}.`);
  }

  if (agentReportScopeRespected !== '' && agentReportScopeRespected !== 'yes') {
    fail(`${agentReportField}: ${agentReportScopeRespectedField} must be 'yes'.`);
  }

  if (agentReportFiles === '') {
    fail(`${agentReportField}: missing '- ${agentReportFilesField}:' in agent report.`);
  } else if (!targetSolidityFiles.some((changedFile) => agentReportFileTokens.has(changedFile))) {
    fail(`${agentReportField}: agent report files do not reference any changed ${changedProductionSolidityFiles.length > 0 ? 'production Solidity' : 'Solidity'} path.`);
  }

  if (agentReportMustPostdateChangedFiles) {
    const existingChangedTargetFiles = targetSolidityFiles
      .map((changedFile) => path.resolve(changedFile))
      .filter((changedFilePath) => fs.existsSync(changedFilePath));
    const staleChangedFile = existingChangedTargetFiles.find(
      (changedFilePath) => fs.statSync(changedFilePath).mtimeMs > agentReportMtimeMs
    );
    if (staleChangedFile) {
      fail(`${agentReportField}: stale writer evidence. '${agentReportPath}' must be regenerated after the latest changed Solidity file '${path.relative(process.cwd(), staleChangedFile)}'.`);
    }
  }
}

const writerDispatchConfirmed = extractField(reviewNote, writerDispatchConfirmedField).trim();
if (writerDispatchConfirmed !== '' && writerDispatchConfirmed !== 'yes') {
  fail(`${writerDispatchConfirmedField}: must be 'yes' for Solidity changes.`);
}

for (const pattern of mainSessionForbiddenPatterns) {
  const regex = new RegExp(pattern);
  if (changedFiles.some((changedFile) => regex.test(changedFile)) && implementationOwner === mainSessionRole) {
    fail(`${implementationOwnerField}: '${mainSessionRole}' is forbidden for the current Solidity write paths.`);
    break;
  }
}

const matchedRequiredOwnersForTargetFiles = new Set();
for (const changedFile of targetSolidityFiles) {
  for (const [pattern, owner] of Object.entries(requiredWriterPatterns)) {
    const regex = new RegExp(pattern);
    if (regex.test(changedFile)) {
      matchedRequiredOwnersForTargetFiles.add(owner);
    }
  }
}

const taskBriefSemanticDimensions = taskBrief === '' ? [] : tokenizeField(extractField(taskBrief, taskBriefSemanticDimensionsField));
const taskBriefSourceDocs = taskBrief === '' ? [] : tokenizeField(extractField(taskBrief, taskBriefSourceOfTruthField));
const taskBriefExternalSources = taskBrief === '' ? [] : tokenizeField(extractField(taskBrief, taskBriefExternalSourcesField));
const taskBriefCriticalAssumptions = taskBrief === '' ? [] : tokenizeField(extractField(taskBrief, taskBriefCriticalAssumptionsField));
const taskBriefFilesInScopeTokens = taskBrief === '' ? new Set() : new Set(extractPathTokens(extractField(taskBrief, taskBriefFilesInScopeField)));
const taskBriefDefaultWriterRole = taskBrief === '' ? '' : extractField(taskBrief, taskBriefDefaultWriterRoleField).trim();
const taskBriefWritePermissionTokens = taskBrief === '' ? new Set() : new Set(extractPathTokens(extractField(taskBrief, taskBriefWritePermissionsField)));

if (taskBrief !== '') {
  for (const field of taskBriefRequiredFields) {
    const value = extractField(taskBrief, field).trim();
    if (value === '') {
      fail(`${taskBriefField}: missing task brief field '${field}'.`);
      continue;
    }
    if (taskBriefBooleanFields.includes(field) && value !== 'yes' && value !== 'no') {
      fail(`${taskBriefField}: field '${field}' must be 'yes' or 'no'.`);
    }
  }

  const taskBriefImplementationOwner = extractField(taskBrief, taskBriefImplementationOwnerField).trim();
  const taskBriefRequiredRoles = extractField(taskBrief, taskBriefRequiredRolesField).trim();
  const taskBriefRequiredVerifierCommands = extractField(taskBrief, taskBriefRequiredVerifierCommandsField).trim();
  const taskBriefRequiresCodexReview = taskBriefRequiredVerifierCommands.toLowerCase().includes(codexReviewTaskBriefToken.toLowerCase());
  const taskBriefReviewNoteRequired = extractField(taskBrief, taskBriefReviewNoteRequiredField).trim();
  const taskBriefDispatchBackend = extractField(taskBrief, taskBriefDispatchBackendField).trim();
  const taskBriefDispatchTarget = extractField(taskBrief, taskBriefDispatchTargetField).trim();

  if (taskBriefImplementationOwner !== '' && implementationOwner !== '' && taskBriefImplementationOwner !== implementationOwner) {
    fail(`${taskBriefImplementationOwnerField}: task brief owner '${taskBriefImplementationOwner}' does not match review note ${implementationOwnerField} '${implementationOwner}'.`);
  }

  const expectedDefaultRoles = classifierRequiredRoles.length > 0
    ? classifierRequiredRoles
    : (changedProductionSolidityFiles.length > 0 ? srcDefaultRoles : testDefaultRoles);
  if (taskBriefRequiredRoles !== '') {
    ensureTokensPresent(taskBriefRequiredRolesField, expectedDefaultRoles, taskBriefRequiredRoles, 'quality_gate default roles', failures);
  }

  const taskBriefClassification = extractField(taskBrief, taskBriefChangeClassificationField).trim();
  const taskBriefVerifierProfile = extractField(taskBrief, taskBriefVerifierProfileField).trim();

  if (taskBriefClassification !== '' && classifierClassification !== 'none' && taskBriefClassification !== classifierClassification) {
    fail(`${taskBriefChangeClassificationField}: task brief classification '${taskBriefClassification}' does not match classifier result '${classifierClassification}'.`);
  }

  if (taskBriefVerifierProfile !== '' && classifierVerifierProfile !== 'none' && taskBriefVerifierProfile !== classifierVerifierProfile) {
    fail(`${taskBriefVerifierProfileField}: task brief verifier profile '${taskBriefVerifierProfile}' does not match classifier result '${classifierVerifierProfile}'.`);
  }

  if (changedProductionSolidityFiles.length > 0 && taskBriefReviewNoteRequired !== 'yes') {
    fail(`${taskBriefReviewNoteRequiredField}: must be 'yes' for production Solidity changes.`);
  }

  if (isNoneLike(taskBriefDispatchBackend)) {
    fail(`${taskBriefDispatchBackendField}: cannot be 'none' for Solidity changes.`);
  }

  if (isNoneLike(taskBriefDispatchTarget)) {
    fail(`${taskBriefDispatchTargetField}: cannot be 'none' for Solidity changes.`);
  }

  if (isNoneLike(taskBriefRequiredVerifierCommands)) {
    fail(`${taskBriefRequiredVerifierCommandsField}: cannot be 'none' for Solidity changes.`);
  } else if (localCodexReviewRequired) {
    ensureTokensPresent(taskBriefRequiredVerifierCommandsField, [codexReviewTaskBriefToken], taskBriefRequiredVerifierCommands, 'verifier.codex_review.task_brief_token', failures);
  }

  if (!targetSolidityFiles.every((changedFile) => taskBriefFilesInScopeTokens.has(changedFile))) {
    fail(`${taskBriefFilesInScopeField}: task brief does not scope the changed ${changedProductionSolidityFiles.length > 0 ? 'production Solidity' : 'Solidity'} path set.`);
  }

  if (matchedRequiredOwnersForTargetFiles.size > 0) {
    if (taskBriefDefaultWriterRole === '') {
      fail(`${taskBriefDefaultWriterRoleField}: must be non-empty for the changed Solidity scope and match required writer role(s): ${Array.from(matchedRequiredOwnersForTargetFiles).join(', ')}`);
    } else if (!matchedRequiredOwnersForTargetFiles.has(taskBriefDefaultWriterRole)) {
      fail(`${taskBriefDefaultWriterRoleField}: '${taskBriefDefaultWriterRole}' does not match required writer role(s) for the changed Solidity scope: ${Array.from(matchedRequiredOwnersForTargetFiles).join(', ')}`);
    }
  }

  if (!targetSolidityFiles.every((changedFile) => taskBriefWritePermissionTokens.has(changedFile))) {
    fail(`${taskBriefWritePermissionsField}: task brief does not authorize the changed ${changedProductionSolidityFiles.length > 0 ? 'production Solidity' : 'Solidity'} path set.`);
  }
}

const reviewCommandsRun = extractField(reviewNote, 'Commands run').trim();
const reviewCodexSummary = extractField(reviewNote, codexReviewSummaryField).trim();
const reviewCodexEvidence = extractField(reviewNote, codexReviewEvidenceField).trim();
const reviewMentionsCodexReview =
  reviewCodexSummary !== '' ||
  reviewCodexEvidence !== '' ||
  codexReviewCommandTokens.some((token) => reviewCommandsRun.toLowerCase().includes(String(token).toLowerCase()));
const shouldRequireCodexReview =
  changedProductionSolidityFiles.length > 0 &&
  (
    localCodexReviewRequired ||
    (
      taskBrief !== '' &&
      extractField(taskBrief, taskBriefRequiredVerifierCommandsField).trim().toLowerCase().includes(codexReviewTaskBriefToken.toLowerCase())
    )
  );

if (changedProductionSolidityFiles.length > 0 && (shouldRequireCodexReview || reviewMentionsCodexReview)) {
  if (shouldRequireCodexReview && reviewCodexSummary === '') {
    fail(`${codexReviewSummaryField}: missing required Solidity review-note field.`);
  }

  if (shouldRequireCodexReview && reviewCodexEvidence === '') {
    fail(`${codexReviewEvidenceField}: missing required Solidity review-note field.`);
  }

  if (reviewCodexSummary !== '' && isNoneLike(reviewCodexSummary)) {
    fail(`${codexReviewSummaryField}: cannot be 'none' for production Solidity changes.`);
  }

  if (reviewCodexEvidence !== '' && isNoneLike(reviewCodexEvidence)) {
    fail(`${codexReviewEvidenceField}: cannot be 'none' for production Solidity changes.`);
  }

  if (shouldRequireCodexReview || reviewCommandsRun !== '') {
    ensureAnyTokenPresent('Commands run', codexReviewCommandTokens, reviewCommandsRun, 'verifier.codex_review.command_tokens', failures);
  }

  if (reviewCodexEvidence !== '') {
    ensureAnyTokenPresent(codexReviewEvidenceField, codexReviewCommandTokens, reviewCodexEvidence, 'verifier.codex_review.command_tokens', failures);
  }
}

const hasSemanticSensitiveChange = (classifierClassification === 'prod-semantic' || classifierClassification === 'high-risk') && changedSolidityFiles.some((changedFile) =>
  semanticSensitivePatterns.some((pattern) => new RegExp(pattern).test(changedFile))
);

const hasExplicitBriefAlignmentRequirements =
  changedProductionSolidityFiles.length > 0 &&
  (
    taskBriefSemanticDimensions.length > 0 ||
    taskBriefSourceDocs.length > 0 ||
    taskBriefExternalSources.length > 0 ||
    taskBriefCriticalAssumptions.length > 0
  );

if ((hasSemanticSensitiveChange || hasExplicitBriefAlignmentRequirements) && taskBrief !== '') {
  const reviewSemanticDimensions = extractField(reviewNote, semanticDimensionsField).trim();
  const reviewSourceOfTruth = extractField(reviewNote, sourceOfTruthField).trim();
  const reviewExternalFacts = extractField(reviewNote, externalFactsField).trim();
  const reviewLocalControlFlow = extractField(reviewNote, localControlFlowField).trim();
  const reviewEvidenceChain = extractField(reviewNote, evidenceChainField).trim();
  const reviewSemanticAlignment = extractField(reviewNote, semanticAlignmentSummaryField).trim();
  const reviewCriticalAssumptions = extractField(reviewNote, criticalAssumptionsField).trim();

  if (isNoneLike(reviewSemanticDimensions)) {
    fail(`${semanticDimensionsField}: cannot be 'none' when semantic alignment is required for the current production Solidity change.`);
  }

  if (isNoneLike(reviewSourceOfTruth)) {
    fail(`${sourceOfTruthField}: cannot be 'none' when semantic alignment is required for the current production Solidity change.`);
  }

  if (isNoneLike(reviewLocalControlFlow)) {
    fail(`${localControlFlowField}: cannot be 'none' when semantic alignment is required for the current production Solidity change.`);
  }

  if (isNoneLike(reviewSemanticAlignment)) {
    fail(`${semanticAlignmentSummaryField}: cannot be 'none' when semantic alignment is required for the current production Solidity change.`);
  }

  if (reviewEvidenceChain !== 'yes') {
    fail(`${evidenceChainField}: must be 'yes' when semantic alignment is required for the current production Solidity change.`);
  }

  if (taskBriefSemanticDimensions.length > 0) {
    ensureTokensPresent(semanticDimensionsField, taskBriefSemanticDimensions, reviewSemanticDimensions, 'Task Brief Semantic review dimensions', failures);
  }

  if (taskBriefSourceDocs.length > 0) {
    ensureTokensPresent(sourceOfTruthField, taskBriefSourceDocs, reviewSourceOfTruth, 'Task Brief Source-of-truth docs', failures);
  }

  if (taskBriefExternalSources.length > 0) {
    if (isNoneLike(reviewExternalFacts)) {
      fail(`${externalFactsField}: cannot be 'none' when the Task Brief declares external sources.`);
    } else {
      ensureTokensPresent(externalFactsField, taskBriefExternalSources, reviewExternalFacts, 'Task Brief External sources required', failures);
    }
  }

  if (reviewEvidenceChain === 'yes' && /needs verification/i.test(reviewExternalFacts)) {
    fail(`${externalFactsField}: cannot stay at 'needs verification' when ${evidenceChainField} is 'yes'.`);
  }

  if (taskBriefCriticalAssumptions.length > 0) {
    if (isNoneLike(reviewCriticalAssumptions)) {
      fail(`${criticalAssumptionsField}: cannot be 'none' when the Task Brief declares Critical assumptions to prove or reject.`);
    } else {
      ensureTokensPresent(criticalAssumptionsField, taskBriefCriticalAssumptions, reviewCriticalAssumptions, 'Task Brief Critical assumptions to prove or reject', failures);
    }
  }
}

if (changedProductionSolidityFiles.length > 0 && agentReportMtimeMs !== null) {
  const reviewNoteMtimeMs = fs.statSync(reviewNotePath).mtimeMs;
  if (reviewNoteMustPostdateAgentReport && reviewNoteMtimeMs < agentReportMtimeMs) {
    fail(`review note: stale reviewer summary. '${path.relative(process.cwd(), reviewNotePath)}' must be regenerated after the current writer Agent Report.`);
  }

  for (const field of requiredFreshnessFields) {
    const rawValue = extractField(reviewNote, field).trim();
    const fieldIsRequired = solidityRequiredFields.includes(field);
    if (rawValue === '' || isNoneLike(rawValue)) {
      if (fieldIsRequired) {
        fail(`${field}: stale-evidence check requires a concrete artifact path for production Solidity changes.`);
      }
      continue;
    }

    const artifactPaths = extractPathTokens(rawValue).map((artifactPath) => path.resolve(artifactPath));
    if (artifactPaths.length === 0) {
      fail(`${field}: stale-evidence check requires at least one artifact path in the owner-prefixed source value.`);
      continue;
    }

    const existingArtifactPaths = artifactPaths.filter((artifactPath) => fs.existsSync(artifactPath));
    if (existingArtifactPaths.length === 0) {
      fail(`${field}: referenced artifact path(s) do not exist for stale-evidence validation.`);
      continue;
    }

    const freshestArtifactPath = existingArtifactPaths.reduce((latestPath, currentPath) =>
      fs.statSync(currentPath).mtimeMs > fs.statSync(latestPath).mtimeMs ? currentPath : latestPath
    );

    if (fs.statSync(freshestArtifactPath).mtimeMs < agentReportMtimeMs) {
      fail(`${field}: stale evidence. Referenced artifact '${path.relative(process.cwd(), freshestArtifactPath)}' predates the current writer Agent Report and must be regenerated.`);
    }
  }
}

if (failures.length > 0) {
  for (const failure of failures) {
    console.error(`[check-solidity-review-note] ERROR: ${failure}`);
  }
  process.exit(1);
}
EOF
