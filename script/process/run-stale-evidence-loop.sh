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

codex_review_task_brief_token="$(read_policy_value verifier.codex_review.task_brief_token 'npm run codex:review')"
review_note_directory="$(read_policy_value quality_gate.review_note_directory 'docs/reviews')"
agent_report_directory="$(read_policy_value agents.agent_report_directory 'docs/agent-reports')"
task_brief_directory="$(read_policy_value agents.task_brief_directory 'docs/task-briefs')"

load_changed_files_from_ci() {
    if [ -n "${QUALITY_GATE_CHANGESET_FILE_LIST:-}" ] && [ -f "${QUALITY_GATE_CHANGESET_FILE_LIST}" ]; then
        cat "${QUALITY_GATE_CHANGESET_FILE_LIST}"
        return
    fi

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

discover_trigger_artifact() {
    local changed_files_file="$1"
    shift
    local candidates=("$@")

    if [ "${#candidates[@]}" -eq 0 ]; then
        return 1
    fi

    TASK_BRIEF_DIRECTORY="$task_brief_directory" node - "$changed_files_file" "${candidates[@]}" <<'EOF'
const fs = require('fs');

const [, , changedFilesPath, ...candidates] = process.argv;
const changedFiles = fs.readFileSync(changedFilesPath, 'utf8').split(/\r?\n/).filter(Boolean);
const taskBriefDirectory = process.env.TASK_BRIEF_DIRECTORY || 'docs/task-briefs';
const changedSolidityFiles = changedFiles.filter((file) => /^(src|script|test)\/.*\.sol$/.test(file));
const changedProductionSolidityFiles = changedFiles.filter((file) => /^(src|script)\/.*\.sol$/.test(file));
const targetSolidityFiles = changedProductionSolidityFiles.length > 0 ? changedProductionSolidityFiles : changedSolidityFiles;
const changedSpecFiles = changedFiles.filter((file) => /^(docs\/spec\/.*|docs\/superpowers\/specs\/.*)$/.test(file));
const changedSet = new Set(changedFiles);
const changedTaskBriefFiles = changedFiles.filter((file) => file.startsWith(`${taskBriefDirectory}/`) && fs.existsSync(file));

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

function isTruthy(value) {
  return /^(yes|true|1)$/i.test(String(value || '').trim());
}

const briefDeclaredSpecPaths = [];
for (const briefPath of changedTaskBriefFiles) {
  const brief = fs.readFileSync(briefPath, 'utf8');
  if (
    extractField(brief, 'Artifact type').trim() === 'spec'
    || isTruthy(extractField(brief, 'Spec review required'))
  ) {
    for (const artifactPath of extractPathTokens(extractField(brief, 'Spec artifact paths'))) {
      briefDeclaredSpecPaths.push(artifactPath);
    }
  }
}

const matching = candidates.filter((candidate) => {
  const document = fs.readFileSync(candidate, 'utf8');

  if (document.startsWith('# review-note')) {
    const filesReviewed = extractField(document, 'Files reviewed');
    const reviewedTokens = new Set(extractPathTokens(filesReviewed));
    return targetSolidityFiles.some((changedFile) => reviewedTokens.has(changedFile));
  }

  if (document.startsWith('# Agent Report')) {
    const role = extractField(document, 'Role');
    if (role !== 'spec-reviewer') return false;

    const filesReviewed = extractField(document, 'Files touched/reviewed');
    const reviewedTokens = new Set(extractPathTokens(filesReviewed));
    const taskBriefPath = extractField(document, 'Task Brief path');
    const taskBrief = taskBriefPath && fs.existsSync(taskBriefPath) ? fs.readFileSync(taskBriefPath, 'utf8') : '';
    const declaredSpecPaths = taskBrief && (
      extractField(taskBrief, 'Artifact type').trim() === 'spec'
      || isTruthy(extractField(taskBrief, 'Spec review required'))
    )
      ? extractPathTokens(extractField(taskBrief, 'Spec artifact paths'))
      : [];
    const targetSpecFiles = [...new Set([
      ...changedSpecFiles,
      ...briefDeclaredSpecPaths,
      ...(changedSet.has(taskBriefPath) ? declaredSpecPaths : []),
      ...declaredSpecPaths.filter((artifactPath) => changedSet.has(artifactPath)),
      ...declaredSpecPaths.filter((artifactPath) => briefDeclaredSpecPaths.includes(artifactPath))
    ])];
    return targetSpecFiles.some((changedFile) => reviewedTokens.has(changedFile));
  }

  return false;
});

if (matching.length > 0) {
  matching.sort((left, right) => fs.statSync(right).mtimeMs - fs.statSync(left).mtimeMs);
  process.stdout.write(matching[0]);
  process.exit(0);
}

process.exit(1);
EOF
}

changed_files="$(load_changed_files)"

if [ -z "$changed_files" ]; then
    echo "[stale-evidence-loop] no changed files detected."
    exit 0
fi

changed_files_tmp="$(mktemp)"
metadata_tmp="$(mktemp)"
trap 'rm -f "$changed_files_tmp" "$metadata_tmp"' EXIT
printf '%s\n' "$changed_files" > "$changed_files_tmp"

trigger_artifact="${QUALITY_GATE_REVIEW_NOTE:-}"
if [ -z "$trigger_artifact" ]; then
    candidate_artifacts=()
    if [ -d "$review_note_directory" ]; then
        while IFS= read -r candidate; do
            [ -n "$candidate" ] && candidate_artifacts+=("$candidate")
        done < <(find "$review_note_directory" -maxdepth 1 -type f -name '*.md' ! -name 'README.md' ! -name 'TEMPLATE.md' | sort)
    fi

    if [ -d "$agent_report_directory" ]; then
        while IFS= read -r candidate; do
            [ -n "$candidate" ] && candidate_artifacts+=("$candidate")
        done < <(find "$agent_report_directory" -maxdepth 1 -type f -name '*.md' ! -name 'README.md' | sort)
    fi

    if [ "${#candidate_artifacts[@]}" -gt 0 ]; then
        trigger_artifact="$(discover_trigger_artifact "$changed_files_tmp" "${candidate_artifacts[@]}" || true)"
    fi
fi

if [ -z "$trigger_artifact" ] || [ ! -f "$trigger_artifact" ]; then
    echo "[stale-evidence-loop] ERROR: trigger artifact not found. Set QUALITY_GATE_REVIEW_NOTE or provide a discoverable review note / spec-reviewer Agent Report." >&2
    exit 1
fi

trigger_artifact_kind="$(head -n 1 "$trigger_artifact" || true)"
if [ "$trigger_artifact_kind" = "# review-note" ]; then
    set +e
    check_output="$(QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_tmp" QUALITY_GATE_REVIEW_NOTE="$trigger_artifact" bash ./script/process/check-solidity-review-note.sh 2>&1)"
    check_status=$?
    set -e
elif [ "$trigger_artifact_kind" = "# Agent Report" ]; then
    trigger_artifact_role="$(grep -m1 '^- Role:' "$trigger_artifact" | sed 's/^- Role:[[:space:]]*//')"
    if [ "$trigger_artifact_role" != "spec-reviewer" ]; then
        echo "[stale-evidence-loop] ERROR: unsupported agent report role for stale remediation: $trigger_artifact_role" >&2
        exit 1
    fi

    spec_changed_files="$(
        TRIGGER_ARTIFACT_PATH="$trigger_artifact" CHANGED_FILES_PATH="$changed_files_tmp" node - <<'EOF'
const fs = require('fs');

const triggerArtifactPath = process.env.TRIGGER_ARTIFACT_PATH;
const changedFilesPath = process.env.CHANGED_FILES_PATH;
const triggerArtifact = fs.readFileSync(triggerArtifactPath, 'utf8');
const changedFiles = fs.readFileSync(changedFilesPath, 'utf8').split(/\r?\n/).filter(Boolean);

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

const taskBriefPath = extractField(triggerArtifact, 'Task Brief path');
const taskBrief = taskBriefPath && fs.existsSync(taskBriefPath) ? fs.readFileSync(taskBriefPath, 'utf8') : '';
const declaredSpecPaths = extractPathTokens(extractField(taskBrief, 'Spec artifact paths'));
const changedSpecPaths = changedFiles.filter((file) => /^(docs\/spec\/.*|docs\/superpowers\/specs\/.*)$/.test(file));
const currentSpecScope = [...new Set([...changedSpecPaths, ...declaredSpecPaths])];
process.stdout.write(currentSpecScope.join('\n'));
EOF
    )"
    if [ -z "$spec_changed_files" ]; then
        echo "[stale-evidence-loop] no changed spec files detected."
        exit 0
    fi

    trigger_artifact_mtime="$(stat -c %Y "$trigger_artifact")"
    stale_spec_file=""
    while IFS= read -r spec_file; do
        [ -z "$spec_file" ] && continue
        [ -f "$spec_file" ] || continue
        if [ "$(stat -c %Y "$spec_file")" -gt "$trigger_artifact_mtime" ]; then
            stale_spec_file="$spec_file"
            break
        fi
    done <<EOF
$spec_changed_files
EOF

    if [ -n "$stale_spec_file" ]; then
        check_output="[spec-reviewer] ERROR: stale evidence. Referenced artifact '$stale_spec_file' predates the current spec-reviewer Agent Report and must be regenerated."
        check_status=1
    else
        echo "[stale-evidence-loop] no stale evidence detected."
        exit 0
    fi
else
    echo "[stale-evidence-loop] ERROR: unsupported trigger artifact: $trigger_artifact" >&2
    exit 1
fi

if [ "$check_status" -eq 0 ]; then
    echo "[stale-evidence-loop] no stale evidence detected."
    exit 0
fi

if ! printf '%s\n' "$check_output" | grep -qi "stale"; then
    printf '%s\n' "$check_output" >&2
    exit "$check_status"
fi

follow_up_dir="${FOLLOW_UP_BRIEF_OUTPUT_DIR:-$(read_policy_value agents.task_brief_directory 'docs/task-briefs')}"
mkdir -p "$follow_up_dir"

FOLLOW_UP_DIR="$follow_up_dir" REMEDIATION_METADATA_FILE="$metadata_tmp" REMEDIATION_LOOP_DATE="${REMEDIATION_LOOP_DATE:-$(date +%F)}" CHECK_OUTPUT="$check_output" CODEX_REVIEW_TASK_BRIEF_TOKEN="$codex_review_task_brief_token" TRIGGER_ARTIFACT_KIND="$trigger_artifact_kind" node - "$trigger_artifact" "$changed_files_tmp" <<'EOF'
const fs = require('fs');
const path = require('path');

const [, , triggerArtifactPath, changedFilesPath] = process.argv;
const triggerArtifact = fs.readFileSync(triggerArtifactPath, 'utf8');
const changedFiles = fs.readFileSync(changedFilesPath, 'utf8').split(/\r?\n/).filter(Boolean);
const outputDir = process.env.FOLLOW_UP_DIR;
const metadataFile = process.env.REMEDIATION_METADATA_FILE;
const loopDate = process.env.REMEDIATION_LOOP_DATE;
const checkOutput = process.env.CHECK_OUTPUT || '';
const triggerArtifactKind = process.env.TRIGGER_ARTIFACT_KIND || '';

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
  return /^(none|n\/a|na|not applicable)$/i.test(value.trim());
}

function tokenizeField(value) {
  if (!value || isNoneLike(value)) return [];
  return value.split(/[;,]/).map((entry) => entry.trim()).filter(Boolean);
}

function dedupe(items) {
  const seen = new Set();
  return items.filter((item) => {
    if (!item || seen.has(item)) return false;
    seen.add(item);
    return true;
  });
}

function slugify(value) {
  return value
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .replace(/-+/g, '-');
}

function resolveUniqueOutput(basePath) {
  if (!fs.existsSync(basePath)) return basePath;
  const ext = path.extname(basePath);
  const stem = basePath.slice(0, -ext.length);
  let counter = 2;
  while (true) {
    const candidate = `${stem}-${counter}${ext}`;
    if (!fs.existsSync(candidate)) return candidate;
    counter += 1;
  }
}

const triggerArtifactHeader = triggerArtifact.split(/\r?\n/)[0] || '';
const triggerArtifactRole = triggerArtifactHeader === '# Agent Report' ? extractField(triggerArtifact, 'Role') : '';
const taskBriefPath = extractField(triggerArtifact, 'Task Brief path');
const agentReportPath = triggerArtifactHeader === '# Agent Report' ? triggerArtifactPath : extractField(triggerArtifact, 'Agent Report path');
const implementationOwner = extractField(triggerArtifact, 'Implementation owner') || (triggerArtifactRole === 'spec-reviewer' ? 'process-implementer' : 'solidity-implementer');
if (!taskBriefPath || !fs.existsSync(taskBriefPath)) {
  throw new Error(`Task Brief path missing or not found: ${taskBriefPath || '(empty)'}`);
}
if (!agentReportPath || !fs.existsSync(agentReportPath)) {
  throw new Error(`Agent Report path missing or not found: ${agentReportPath || '(empty)'}`);
}

const taskBrief = fs.readFileSync(taskBriefPath, 'utf8');
const agentReport = fs.readFileSync(agentReportPath, 'utf8');
const changedSolidityFiles = changedFiles.filter((file) => /^(src|script|test)\/.*\.sol$/.test(file));
const changedProductionSolidityFiles = changedFiles.filter((file) => /^(src|script)\/.*\.sol$/.test(file));
const targetSolidityFiles = changedProductionSolidityFiles.length > 0 ? changedProductionSolidityFiles : changedSolidityFiles;
const changedSpecFiles = changedFiles.filter((file) => /^(docs\/spec\/.*|docs\/superpowers\/specs\/.*)$/.test(file));
const isSpecSurface = triggerArtifactRole === 'spec-reviewer' || extractField(taskBrief, 'Artifact type').trim() === 'spec' || extractField(taskBrief, 'Spec review required').trim() === 'yes';
const targetSpecFiles = changedSpecFiles;
const targetFiles = isSpecSurface ? targetSpecFiles : targetSolidityFiles;

const originalRequiredRoles = tokenizeField(extractField(taskBrief, 'Required roles'));
const originalOptionalRoles = extractField(taskBrief, 'Optional roles') || 'none';
const defaultWriterRole = extractField(taskBrief, 'Default writer role') || implementationOwner;
const originalArtifactType = extractField(taskBrief, 'Artifact type') || (isSpecSurface ? 'spec' : 'solidity');
const originalSpecReviewRequired = extractField(taskBrief, 'Spec review required') || (isSpecSurface ? 'yes' : 'no');
const originalSpecArtifactPaths = extractField(taskBrief, 'Spec artifact paths') || (isSpecSurface ? targetSpecFiles.join(', ') : 'none');
const filesInScope = extractField(taskBrief, 'Files in scope') || targetFiles.join(', ');
const writePermissions = extractField(taskBrief, 'Write permissions') || filesInScope;
const dispatchBackend = extractField(taskBrief, 'Writer dispatch backend') || 'native-codex-subagents';
const dispatchTarget = extractField(taskBrief, 'Writer dispatch target') || `.codex/agents/${defaultWriterRole}.toml`;
const dispatchScope = extractField(taskBrief, 'Writer dispatch scope') || filesInScope;
const requiredVerifierCommands = extractField(taskBrief, 'Required verifier commands') || (isSpecSurface ? 'npm run docs:check; npm run process:selftest' : 'npm run codex:review');
const requiresCodexReview = !isSpecSurface && String(requiredVerifierCommands).toLowerCase().includes('npm run codex:review');
const originalRequiredArtifacts = extractField(taskBrief, 'Required artifacts') || (isSpecSurface ? 'Task Brief, Agent Report, spec-reviewer Agent Report, verifier evidence' : 'Task Brief, Agent Report, review note');
const reviewNoteRequired = extractField(taskBrief, 'Review note required') || (changedProductionSolidityFiles.length > 0 ? 'yes' : 'no');
const semanticDimensions = extractField(taskBrief, 'Semantic review dimensions') || 'none';
const sourceOfTruthDocs = extractField(taskBrief, 'Source-of-truth docs') || 'none';
const externalSources = extractField(taskBrief, 'External sources required') || 'none';
const criticalAssumptions = extractField(taskBrief, 'Critical assumptions to prove or reject') || 'none';
const requiredOutputFields = extractField(taskBrief, 'Required output fields') || 'none';
const reviewNoteImpact = extractField(taskBrief, 'Review note impact') || 'no';
const originalAcceptanceChecks = extractField(taskBrief, 'Acceptance checks') || 'none';
const originalNonGoals = extractField(taskBrief, 'Non-goals') || 'none';
const originalChangeClassification = extractField(taskBrief, 'Change classification') || 'follow-up-remediation';
const originalKnownFacts = extractField(taskBrief, 'Known facts') || 'none';
const originalOpenQuestions = extractField(taskBrief, 'Open questions / assumptions') || 'none';
const originalOutOfScope = extractField(taskBrief, 'Out of scope') || originalNonGoals || 'none';
const originalIfBlocked = extractField(taskBrief, 'If blocked') || 'stop and return the blocking finding';
const priorFindings = extractField(agentReport, 'Findings') || 'none';
const priorFollowUp = extractField(agentReport, 'Required follow-up') || 'none';
const staleLines = checkOutput
  .split(/\r?\n/)
  .map((line) => line.trim())
  .filter((line) => /stale/i.test(line))
  .map((line) => line.replace(/^\[(check-solidity-review-note|spec-reviewer)\]\s*ERROR:\s*/i, ''));

const requiredRerunRoles = (() => {
  const baseline = [implementationOwner, 'verifier'];
  for (const role of originalRequiredRoles) baseline.push(role);
  return dedupe(baseline);
})();

const downstreamReviewerRoles = requiredRerunRoles.filter((role) => role !== implementationOwner && role !== 'verifier');
const dispatchOrder = dedupe([
  implementationOwner,
  ...downstreamReviewerRoles,
  ...(requiresCodexReview ? ['codex review'] : []),
  'verifier'
]);

const risksToCheckParts = dedupe([
  isSpecSurface
    ? 'stale spec-reviewer Agent Report and verifier evidence must be regenerated against the latest writer Agent Report'
    : 'stale reviewer/verifier evidence must be regenerated against the latest writer Agent Report',
  ...staleLines,
  isNoneLike(priorFollowUp) ? '' : priorFollowUp,
  isNoneLike(priorFindings) ? '' : priorFindings
]);

const reviewerRerunLabel = downstreamReviewerRoles.length > 0
  ? `rerun ${downstreamReviewerRoles.join('/')} against the latest writer Agent Report`
  : 'regenerate fresh verifier evidence against the latest writer Agent Report';

const acceptanceCheckParts = dedupe([
  isNoneLike(originalAcceptanceChecks) ? '' : originalAcceptanceChecks,
  'regenerate the writer Agent Report after the current remediation pass',
  reviewerRerunLabel,
  requiresCodexReview ? 'rerun npm run codex:review after the reviewer pass' : '',
  isSpecSurface
    ? 'rerun verifier and clear stale evidence findings from spec-reviewer Agent Report freshness checks'
    : 'rerun verifier and clear stale evidence findings from check-solidity-review-note.sh'
]);

const nonGoalParts = dedupe([
  isNoneLike(originalNonGoals) ? '' : originalNonGoals,
  'reuse stale reviewer/verifier evidence',
  'expand scope beyond the stale-evidence remediation paths without a new brief'
]);

const knownFactParts = dedupe([
  isNoneLike(originalKnownFacts) ? '' : originalKnownFacts,
  `parent task brief: ${taskBriefPath}`,
  `parent agent report: ${agentReportPath}`,
  `trigger artifact: ${triggerArtifactPath}`
]);

const openQuestionParts = dedupe([
  isNoneLike(originalOpenQuestions) ? '' : originalOpenQuestions,
  'none'
]).filter((item, index, items) => !(item === 'none' && items.length > 1));

const requiredArtifactParts = dedupe([
  ...tokenizeField(originalRequiredArtifacts),
  downstreamReviewerRoles.length > 0
    ? (downstreamReviewerRoles.includes('spec-reviewer')
      ? 'fresh spec-reviewer Agent Report and verifier evidence'
      : `fresh ${downstreamReviewerRoles.join('/')} and verifier evidence`)
    : 'fresh verifier evidence'
]);

const baseSlug = slugify(path.basename(taskBriefPath, path.extname(taskBriefPath))) || 'task-brief';
const outputPath = resolveUniqueOutput(path.join(outputDir, `${loopDate}-${baseSlug}-stale-evidence-remediation.md`));

const lines = [
  '# Follow-up Brief',
  '',
  isSpecSurface
    ? '- Goal: Regenerate fresh spec-reviewer and verifier evidence after stale evidence was detected for the current spec scope.'
    : '- Goal: Regenerate fresh reviewer and verifier evidence after stale evidence was detected for the current Solidity scope.',
  `- Change classification: ${originalChangeClassification}`,
  `- Artifact type: ${originalArtifactType}`,
  `- Spec review required: ${originalSpecReviewRequired}`,
  `- Spec artifact paths: ${originalSpecArtifactPaths}`,
  `- Files in scope: ${filesInScope}`,
  `- Out of scope: ${originalOutOfScope}`,
  `- Known facts: ${knownFactParts.length > 0 ? knownFactParts.join('; ') : 'none'}`,
  `- Open questions / assumptions: ${openQuestionParts.length > 0 ? openQuestionParts.join('; ') : 'none'}`,
  `- Risks to check: ${risksToCheckParts.length > 0 ? risksToCheckParts.join('; ') : 'stale reviewer/verifier evidence must be regenerated against the latest writer Agent Report'}`,
  `- Acceptance checks: ${acceptanceCheckParts.length > 0 ? acceptanceCheckParts.join('; ') : 'rerun reviewer and verifier evidence against the latest writer Agent Report'}`,
  `- Required artifacts: ${requiredArtifactParts.length > 0 ? requiredArtifactParts.join(', ') : 'Task Brief, Agent Report, review note, fresh reviewer/verifier evidence'}`,
  `- Parent Task Brief path: ${taskBriefPath}`,
  `- Parent Agent Report path: ${agentReportPath}`,
  `- Trigger artifact: ${triggerArtifactPath}`,
  `- Trigger stale findings: ${staleLines.length > 0 ? staleLines.join(' | ') : (isSpecSurface ? 'stale spec-reviewer Agent Report detected by freshness checks' : 'stale reviewer/verifier evidence detected by check-solidity-review-note.sh')}`,
  `- Required rerun roles: ${requiredRerunRoles.join(', ')}`,
  `- Dispatch order: ${dispatchOrder.join(' -> ')}`,
  `- If blocked: ${originalIfBlocked}`,
  '',
  '> Carry-over fields from the parent brief',
  '',
  `- Optional roles: ${originalOptionalRoles}`,
  `- Default writer role: ${defaultWriterRole}`,
  `- Implementation owner: ${implementationOwner}`,
  `- Write permissions: ${writePermissions}`,
  `- Writer dispatch backend: ${dispatchBackend}`,
  `- Writer dispatch target: ${dispatchTarget}`,
  `- Writer dispatch scope: ${dispatchScope}`,
  `- Non-goals: ${nonGoalParts.length > 0 ? nonGoalParts.join('; ') : 'reuse stale reviewer/verifier evidence'}`,
  `- Required verifier commands: ${requiredVerifierCommands}`,
  `- Review note required: ${reviewNoteRequired}`,
  `- Semantic review dimensions: ${semanticDimensions}`,
  `- Source-of-truth docs: ${sourceOfTruthDocs}`,
  `- External sources required: ${externalSources}`,
  `- Critical assumptions to prove or reject: ${criticalAssumptions}`,
  `- Required output fields: ${requiredOutputFields}`,
  `- Review note impact: ${reviewNoteImpact}`,
  '- Generated by: script/process/run-stale-evidence-loop.sh'
];

fs.writeFileSync(outputPath, `${lines.join('\n')}\n`);
fs.writeFileSync(
  metadataFile,
  JSON.stringify(
    {
      follow_up_brief_path: outputPath,
      parent_task_brief_path: taskBriefPath,
      parent_agent_report_path: agentReportPath,
      trigger_artifact_path: triggerArtifactPath,
      required_rerun_roles: requiredRerunRoles,
      dispatch_order: dispatchOrder,
      stale_findings: staleLines
    },
    null,
    2
  ) + '\n'
);
EOF

node - "$metadata_tmp" <<'EOF'
const fs = require('fs');

const metadata = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
console.log(`[stale-evidence-loop] stale evidence detected.`);
console.log(`[stale-evidence-loop] follow-up brief written: ${metadata.follow_up_brief_path}`);
console.log(`[stale-evidence-loop] parent task brief: ${metadata.parent_task_brief_path}`);
console.log(`[stale-evidence-loop] parent agent report: ${metadata.parent_agent_report_path}`);
console.log(`[stale-evidence-loop] trigger artifact: ${metadata.trigger_artifact_path}`);
console.log(`[stale-evidence-loop] re-dispatch order: ${metadata.dispatch_order.join(' -> ')}`);
if (metadata.stale_findings.length > 0) {
  console.log(`[stale-evidence-loop] stale findings: ${metadata.stale_findings.join(' | ')}`);
}
EOF

exit 2
