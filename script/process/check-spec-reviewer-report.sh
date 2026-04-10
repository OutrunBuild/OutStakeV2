#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

mode="${QUALITY_GATE_MODE:-staged}"

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

changed_files="$(load_changed_files)"

if [ -z "$changed_files" ]; then
    echo "[check-spec-reviewer-evidence] no changed files detected."
    exit 0
fi

changed_files_tmp="$(mktemp)"
trap 'rm -f "$changed_files_tmp"' EXIT
printf '%s\n' "$changed_files" > "$changed_files_tmp"

task_brief_directory="$(read_policy_value agents.task_brief_directory 'docs/task-briefs')"
agent_report_directory="$(read_policy_value agents.agent_report_directory 'docs/agent-reports')"
spec_surface_pattern="$(read_policy_value quality_gate.spec_surface_pattern '^(docs/spec/.*|docs/superpowers/specs/.*)$')"
docs_check_token="npm run docs:check"
process_selftest_token="npm run process:selftest"

node - "$changed_files_tmp" "$task_brief_directory" "$agent_report_directory" "$spec_surface_pattern" "$docs_check_token" "$process_selftest_token" "${QUALITY_GATE_SPEC_REVIEWER_REPORT:-}" "${QUALITY_GATE_TASK_BRIEF:-}" <<'EOF'
const fs = require('fs');
const path = require('path');

const [
  ,
  ,
  changedFilesPath,
  taskBriefDirectory,
  agentReportDirectory,
  specSurfacePatternSource,
  docsCheckToken,
  processSelftestToken,
  explicitSpecReportPath,
  explicitTaskBriefPath
] = process.argv;

const changedFiles = fs.readFileSync(changedFilesPath, 'utf8').split(/\r?\n/).filter(Boolean);
const specSurfacePattern = new RegExp(specSurfacePatternSource);

function readIfExists(targetPath) {
  if (!targetPath || !fs.existsSync(targetPath) || fs.statSync(targetPath).isDirectory()) return '';
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

function splitList(value) {
  return String(value || '')
    .split(/[;,]/)
    .map((item) => item.trim())
    .filter(Boolean);
}

function dedupe(items) {
  const seen = new Set();
  return items.filter((item) => {
    if (!item || seen.has(item)) return false;
    seen.add(item);
    return true;
  });
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

function listBriefCandidates(directory) {
  if (!directory || !fs.existsSync(directory)) return [];
  return fs
    .readdirSync(directory)
    .filter((entry) => entry.endsWith('.md') && entry !== 'README.md' && entry !== 'TEMPLATE.md')
    .map((entry) => path.join(directory, entry))
    .filter((briefPath) => {
      const document = readIfExists(briefPath);
      return document && isBrief(document) && isSpecBrief(document);
    })
    .sort((left, right) => fs.statSync(right).mtimeMs - fs.statSync(left).mtimeMs);
}

function findLatestReport(directory, role, taskBriefPath) {
  if (!directory || !fs.existsSync(directory)) return '';
  const reports = fs
    .readdirSync(directory)
    .filter((entry) => entry.endsWith('.md') && entry !== 'README.md' && entry !== 'TEMPLATE.md')
    .map((entry) => path.join(directory, entry))
    .filter((reportPath) => {
      const report = readIfExists(reportPath);
      return extractField(report, 'Role').trim() === role
        && extractField(report, 'Task Brief path').trim() === taskBriefPath;
    })
    .sort((left, right) => fs.statSync(right).mtimeMs - fs.statSync(left).mtimeMs);

  return reports[0] || '';
}

const changedSet = new Set(changedFiles);
const changedSpecFiles = changedFiles.filter((file) => specSurfacePattern.test(file));
const changedBriefCandidates = changedFiles
  .filter((file) => file.endsWith('.md') && fs.existsSync(file))
  .filter((file) => {
    const document = readIfExists(file);
    return document && isBrief(document) && isSpecBrief(document);
  })
  .sort((left, right) => fs.statSync(right).mtimeMs - fs.statSync(left).mtimeMs);
const changedAgentReportCandidates = changedFiles
  .filter((file) => file.endsWith('.md') && fs.existsSync(file))
  .filter((file) => {
    const document = readIfExists(file);
    return document.startsWith('# Agent Report');
  })
  .sort((left, right) => fs.statSync(right).mtimeMs - fs.statSync(left).mtimeMs);

let taskBriefPath = explicitTaskBriefPath && fs.existsSync(explicitTaskBriefPath)
  ? explicitTaskBriefPath
  : (changedBriefCandidates[0] || '');

if (!taskBriefPath) {
  for (const reportPath of changedAgentReportCandidates) {
    const report = readIfExists(reportPath);
    const candidateTaskBriefPath = extractField(report, 'Task Brief path').trim();
    const candidateTaskBrief = readIfExists(candidateTaskBriefPath);
    if (candidateTaskBrief && isBrief(candidateTaskBrief) && isSpecBrief(candidateTaskBrief)) {
      taskBriefPath = candidateTaskBriefPath;
      break;
    }
  }
}

if (!taskBriefPath) {
  for (const candidate of listBriefCandidates(taskBriefDirectory)) {
    const document = readIfExists(candidate);
    const declaredSpecPaths = extractPathTokens(extractField(document, 'Spec artifact paths'));
    const filesInScope = extractPathTokens(extractField(document, 'Files in scope'));
    const candidateScope = dedupe([...declaredSpecPaths, ...filesInScope]);
    if (candidateScope.some((scopePath) => changedSet.has(scopePath))) {
      taskBriefPath = candidate;
      break;
    }
  }
}

const taskBrief = readIfExists(taskBriefPath);
const hasSpecSurface = changedSpecFiles.length > 0 || Boolean(taskBrief);

if (!hasSpecSurface) {
  console.log('[check-spec-reviewer-evidence] PASS');
  process.exit(0);
}

const failures = [];
const staleFailures = [];

if (!taskBriefPath || !taskBrief) {
  failures.push('spec surface requires a Task Brief or Follow-up Brief with Artifact type: spec');
}

const artifactType = extractField(taskBrief, 'Artifact type').trim();
const specReviewRequired = extractField(taskBrief, 'Spec review required').trim();
const declaredSpecArtifactPaths = extractPathTokens(extractField(taskBrief, 'Spec artifact paths'));
const specArtifactPaths = dedupe([...declaredSpecArtifactPaths, ...changedSpecFiles]);
const requiredArtifacts = splitList(extractField(taskBrief, 'Required artifacts'));
const requiredVerifierCommands = extractField(taskBrief, 'Required verifier commands');
const requiredRoles = splitList(extractField(taskBrief, 'Required roles'));
const defaultWriterRole = extractField(taskBrief, 'Default writer role').trim() || extractField(taskBrief, 'Implementation owner').trim() || 'process-implementer';

if (taskBrief && artifactType.toLowerCase() !== 'spec') {
  failures.push(`Artifact type must be spec for spec surface briefs: ${taskBriefPath}`);
}

if (taskBrief && !isTruthy(specReviewRequired)) {
  failures.push(`Spec review required must be yes for spec surface briefs: ${taskBriefPath}`);
}

if (taskBrief && specArtifactPaths.length === 0) {
  failures.push(`Spec artifact paths must list the current spec scope: ${taskBriefPath}`);
}

for (const requiredRole of ['spec-reviewer', 'verifier']) {
  if (taskBrief && !requiredRoles.includes(requiredRole)) {
    failures.push(`Required roles must include '${requiredRole}': ${taskBriefPath}`);
  }
}

for (const requiredArtifact of ['Task Brief', 'writer evidence', 'spec review evidence', 'verifier evidence']) {
  if (taskBrief && !requiredArtifacts.includes(requiredArtifact)) {
    failures.push(`Required artifacts must include '${requiredArtifact}': ${taskBriefPath}`);
  }
}

for (const requiredCommand of [docsCheckToken, processSelftestToken]) {
  if (taskBrief && !requiredVerifierCommands.includes(requiredCommand)) {
    failures.push(`Required verifier commands must include '${requiredCommand}': ${taskBriefPath}`);
  }
}

const writerReportPath = taskBrief ? findLatestReport(agentReportDirectory, defaultWriterRole, taskBriefPath) : '';
const specReportPath = explicitSpecReportPath && fs.existsSync(explicitSpecReportPath)
  ? explicitSpecReportPath
  : (taskBrief ? findLatestReport(agentReportDirectory, 'spec-reviewer', taskBriefPath) : '');

if (taskBrief && !writerReportPath) {
  failures.push(`writer Agent Report not found for ${defaultWriterRole}: ${taskBriefPath}`);
}

if (taskBrief && !specReportPath) {
  failures.push(`spec-reviewer Agent Report not found: ${taskBriefPath}`);
}

const writerReport = readIfExists(writerReportPath);
const specReport = readIfExists(specReportPath);
const reviewedPaths = new Set(extractPathTokens(extractField(specReport, 'Files touched/reviewed')));

if (specReport && extractField(specReport, 'Role').trim() !== 'spec-reviewer') {
  failures.push(`spec-reviewer Agent Report must be written by spec-reviewer: ${specReportPath}`);
}

if (specReport && extractField(specReport, 'Task Brief path').trim() !== taskBriefPath) {
  failures.push(`spec-reviewer Agent Report must point to the current Task Brief: ${specReportPath}`);
}

if (writerReport && extractField(writerReport, 'Task Brief path').trim() !== taskBriefPath) {
  failures.push(`writer Agent Report must point to the current Task Brief: ${writerReportPath}`);
}

for (const specArtifactPath of specArtifactPaths) {
  if (!reviewedPaths.has(specArtifactPath)) {
    failures.push(`spec-reviewer Agent Report must cover spec artifact '${specArtifactPath}': ${specReportPath || taskBriefPath}`);
  }
}

if (writerReportPath && specReportPath) {
  if (fs.statSync(writerReportPath).mtimeMs >= fs.statSync(specReportPath).mtimeMs) {
    staleFailures.push(`spec-reviewer Agent Report must postdate the current writer Agent Report: ${specReportPath}`);
  }
}

if (specReportPath) {
  const specReportMtime = fs.statSync(specReportPath).mtimeMs;
  for (const specArtifactPath of specArtifactPaths) {
    if (!fs.existsSync(specArtifactPath)) {
      failures.push(`spec artifact path not found: ${specArtifactPath}`);
      continue;
    }
    if (fs.statSync(specArtifactPath).mtimeMs >= specReportMtime) {
      staleFailures.push(`spec-reviewer Agent Report must postdate spec artifact '${specArtifactPath}': ${specReportPath}`);
    }
  }
}

if (staleFailures.length > 0) {
  for (const message of staleFailures) {
    console.error(`[spec-reviewer] ERROR: stale evidence. ${message}`);
  }
  process.exit(1);
}

if (failures.length > 0) {
  for (const message of failures) {
    console.error(`[spec-reviewer] ERROR: ${message}`);
  }
  process.exit(1);
}

console.log('[check-spec-reviewer-evidence] PASS');
EOF
