#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

tmp_dir="$(mktemp -d)"
bin_dir="$tmp_dir/bin"
npm_log="$tmp_dir/npm.log"
command_log="$tmp_dir/commands.log"
wrapper_log="$tmp_dir/wrapper.log"
wrapper_file_list="$tmp_dir/wrapper-file-list.txt"
wrapper_changeset_file_list="$tmp_dir/wrapper-changeset-file-list.txt"
check_solhint_output="$tmp_dir/check-solhint.out"
quick_output="$tmp_dir/quality-quick.out"
gate_output="$tmp_dir/quality-gate.out"
changed_files_path="$tmp_dir/changed-files.txt"
diff_file="$tmp_dir/change.diff"
created_src_fixture=""
created_test_fixture=""
created_script_fixture=""
created_spec_fixture=""
created_spec_task_brief_fixture=""
created_spec_writer_report_fixture=""
created_spec_reviewer_report_fixture=""

cleanup() {
    if [ -n "$created_src_fixture" ] && [ -f "$created_src_fixture" ]; then
        rm -f "$created_src_fixture"
    fi
    if [ -n "$created_test_fixture" ] && [ -f "$created_test_fixture" ]; then
        rm -f "$created_test_fixture"
    fi
    if [ -n "$created_script_fixture" ] && [ -f "$created_script_fixture" ]; then
        rm -f "$created_script_fixture"
    fi
    if [ -n "$created_spec_fixture" ] && [ -f "$created_spec_fixture" ]; then
        rm -f "$created_spec_fixture"
    fi
    if [ -n "$created_spec_task_brief_fixture" ] && [ -f "$created_spec_task_brief_fixture" ]; then
        rm -f "$created_spec_task_brief_fixture"
    fi
    if [ -n "$created_spec_writer_report_fixture" ] && [ -f "$created_spec_writer_report_fixture" ]; then
        rm -f "$created_spec_writer_report_fixture"
    fi
    if [ -n "$created_spec_reviewer_report_fixture" ] && [ -f "$created_spec_reviewer_report_fixture" ]; then
        rm -f "$created_spec_reviewer_report_fixture"
    fi
    rm -rf "$tmp_dir"
}
trap cleanup EXIT

existing_src_file="$(rg --files src -g '*.sol' 2>/dev/null | head -n 1 || true)"
existing_test_file="$(rg --files test -g '*.sol' 2>/dev/null | head -n 1 || true)"
existing_script_file="$(rg --files script -g '*.sol' 2>/dev/null | head -n 1 || true)"

if [ -z "$existing_src_file" ]; then
    mkdir -p src
    created_src_fixture="src/__quality_gates_selftest__.sol"
    printf '%s\n' 'pragma solidity ^0.8.20; contract QualityGateFixture {}' > "$created_src_fixture"
    existing_src_file="$created_src_fixture"
fi

if [ -z "$existing_test_file" ]; then
    mkdir -p test
    created_test_fixture="test/__quality_gates_selftest__.sol"
    printf '%s\n' 'pragma solidity ^0.8.20; contract QualityGateTestFixture {}' > "$created_test_fixture"
    existing_test_file="$created_test_fixture"
fi

if [ -z "$existing_script_file" ]; then
    mkdir -p script
    created_script_fixture="script/__quality_gates_selftest__.sol"
    printf '%s\n' 'pragma solidity ^0.8.20; contract QualityGateScriptFixture {}' > "$created_script_fixture"
    existing_script_file="$created_script_fixture"
fi

mkdir -p docs/superpowers/specs
created_spec_fixture="docs/superpowers/specs/__quality_gates_selftest__.md"
printf '%s\n' '# Spec Surface Fixture' '- Goal: quality gate spec surface selftest' > "$created_spec_fixture"

mkdir -p docs/task-briefs docs/agent-reports
created_spec_task_brief_fixture="docs/task-briefs/2026-04-10-quality-gates-spec-task-brief.md"
created_spec_writer_report_fixture="docs/agent-reports/2026-04-10-quality-gates-spec-writer.md"
created_spec_reviewer_report_fixture="docs/agent-reports/2026-04-10-quality-gates-spec-reviewer.md"
cat > "$created_spec_task_brief_fixture" <<EOF
# Task Brief

- Goal: quality gate spec surface selftest
- Change classification: process-surface
- Change classification rationale: spec surface evidence routing selftest
- Change type: none
- Files in scope: $created_spec_fixture
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
- Spec artifact paths: $created_spec_fixture
- Write permissions: $created_spec_fixture
- Writer dispatch backend: native-codex-subagents
- Writer dispatch target: .codex/agents/process-implementer.toml
- Writer dispatch scope: $created_spec_fixture
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
- If blocked: stop and return the stale evidence blocker
EOF

cat > "$created_spec_writer_report_fixture" <<EOF
# Agent Report

- Role: process-implementer
- Summary: updated the spec surface fixture
- Task Brief path: $created_spec_task_brief_fixture
- Scope / ownership respected: yes
- Files touched/reviewed: $created_spec_fixture
- Findings: none
- Required follow-up: spec-reviewer -> verifier
- Commands run: npm run docs:check
- Evidence: selftest fixture
- Residual risks: verifier still pending
EOF

cat > "$created_spec_reviewer_report_fixture" <<EOF
# Agent Report

- Role: spec-reviewer
- Summary: reviewed the spec surface fixture
- Task Brief path: $created_spec_task_brief_fixture
- Scope / ownership respected: yes
- Files touched/reviewed: $created_spec_fixture
- Findings: none
- Required follow-up: verifier
- Commands run: docs review
- Evidence: selftest fixture
- Residual risks: verifier still pending
EOF

mkdir -p "$bin_dir"

cat > "$bin_dir/npm" <<EOF
#!/bin/bash
set -euo pipefail
printf 'QUALITY_GATE_MODE=%s QUALITY_GATE_FILE_LIST=%s QUALITY_GATE_CHANGESET_FILE_LIST=%s CMD=%s\n' "\${QUALITY_GATE_MODE:-}" "\${QUALITY_GATE_FILE_LIST:-}" "\${QUALITY_GATE_CHANGESET_FILE_LIST:-}" "\$*" >> "$npm_log"
EOF
chmod +x "$bin_dir/npm"

cat > "$bin_dir/forge" <<EOF
#!/bin/bash
set -euo pipefail
printf 'forge %s\n' "\$*" >> "$command_log"
EOF
chmod +x "$bin_dir/forge"

cat > "$bin_dir/npx" <<EOF
#!/bin/bash
set -euo pipefail

if [ "\${1:-}" = "solhint" ]; then
  shift
  has_solidity_input=0
  has_non_ignored_input=0

  for arg in "\$@"; do
    case "\$arg" in
      -*)
        continue
        ;;
      *.sol)
        has_solidity_input=1
        case "\$arg" in
          test/*)
            ;;
          *)
            has_non_ignored_input=1
            ;;
        esac
        ;;
    esac
  done

  if [ "\$has_solidity_input" -eq 1 ] && [ "\$has_non_ignored_input" -eq 0 ]; then
    printf 'No files to lint!\n' >&2
    exit 1
  fi

  exit 0
fi

exit 0
EOF
chmod +x "$bin_dir/npx"

cat > "$bin_dir/git" <<EOF
#!/bin/bash
set -euo pipefail

if [ "\${1:-}" = "rev-parse" ] && [ "\${2:-}" = "--show-toplevel" ]; then
  printf '%s\n' "$repo_root"
  exit 0
fi

if [ "\${1:-}" = "diff" ] && [ "\${2:-}" = "--cached" ] && [ "\${3:-}" = "--name-only" ] && [ "\${4:-}" = "--diff-filter=ACMRD" ]; then
  cat "$changed_files_path"
  exit 0
fi

if [ "\${1:-}" = "diff" ] && [ "\${2:-}" = "--name-only" ] && [ "\${3:-}" = "HEAD~1..HEAD" ]; then
  cat "$changed_files_path"
  exit 0
fi

if [ "\${1:-}" = "ls-files" ]; then
  /usr/bin/git ls-files
  exit 0
fi

exec /usr/bin/git "\$@"
EOF
chmod +x "$bin_dir/git"

cat > "$bin_dir/bash" <<EOF
#!/bin/bash
set -euo pipefail
if [ "\${1:-}" = "-n" ]; then
  printf 'bash %s %s\n' "\$1" "\$2" >> "$command_log"
  exit 0
fi

case "\${1:-}" in
  ./script/process/quality-gate.sh)
    printf 'QUALITY_GATE_MODE=%s QUALITY_GATE_FILE_LIST=%s QUALITY_GATE_CHANGESET_FILE_LIST=%s\n' "\${QUALITY_GATE_MODE:-}" "\${QUALITY_GATE_FILE_LIST:-}" "\${QUALITY_GATE_CHANGESET_FILE_LIST:-}" >> "$wrapper_log"
    if [ -n "\${QUALITY_GATE_FILE_LIST:-}" ] && [ -f "\${QUALITY_GATE_FILE_LIST:-}" ]; then
      cat "\${QUALITY_GATE_FILE_LIST}" > "$wrapper_file_list"
    fi
    if [ -n "\${QUALITY_GATE_CHANGESET_FILE_LIST:-}" ] && [ -f "\${QUALITY_GATE_CHANGESET_FILE_LIST:-}" ]; then
      cat "\${QUALITY_GATE_CHANGESET_FILE_LIST}" > "$wrapper_changeset_file_list"
    fi
    exit 0
    ;;
  ./script/process/check-solhint.sh)
    printf 'bash %s\n' "\$1" >> "$command_log"
    /bin/bash "./script/process/check-solhint.sh" "\${@:2}"
    ;;
  ./script/process/check-natspec.sh|./script/process/check-coverage.sh|./script/process/check-slither.sh|./script/process/check-gas-report.sh|./script/process/check-solidity-review-note.sh|./script/process/check-spec-reviewer-evidence.sh|./script/process/run-stale-evidence-loop.sh|./script/process/check-rule-map.sh)
    printf 'bash %s\n' "\$1" >> "$command_log"
    if [ "\$1" = "./script/process/check-solidity-review-note.sh" ]; then
      printf '[check-solidity-review-note] PASS\n'
    elif [ "\$1" = "./script/process/check-spec-reviewer-evidence.sh" ]; then
      printf '[check-spec-reviewer-evidence] PASS\n'
    fi
    exit 0
    ;;
esac

exec /bin/bash "\$@"
EOF
chmod +x "$bin_dir/bash"

run_quality_script() {
    local script_name="$1"
    local changed_file="$2"
    local output_file="$3"
    local forced_classification="${4:-}"
    local diff_content="${5:-}"
    local gate_mode="${6:-ci}"

    : > "$npm_log"
    : > "$command_log"
    printf '%s\n' "$changed_file" > "$changed_files_path"
    printf '%s\n' "$diff_content" > "$diff_file"
    if [ "$gate_mode" = "ci" ]; then
        PATH="$bin_dir:$PATH" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" CHANGE_CLASSIFIER_FORCE="$forced_classification" CHANGE_CLASSIFIER_DIFF_FILE="$diff_file" \
            /bin/bash "./script/process/${script_name}" >"$output_file" 2>&1
        return
    fi

    PATH="$bin_dir:$PATH" QUALITY_GATE_FILE_LIST="$changed_files_path" CHANGE_CLASSIFIER_FORCE="$forced_classification" CHANGE_CLASSIFIER_DIFF_FILE="$diff_file" \
        /bin/bash "./script/process/${script_name}" >"$output_file" 2>&1
}

assert_contains() {
    local needle="$1"
    local haystack_file="$2"
    local context="$3"

    if ! grep -qF "$needle" "$haystack_file"; then
        echo "Expected '$needle' in $context"
        cat "$haystack_file"
        exit 1
    fi
}

if [ ! -f "./script/process/lib/quality-common.sh" ]; then
    echo "Expected shared helper ./script/process/lib/quality-common.sh"
    exit 1
fi

assert_contains "source ./script/process/lib/quality-common.sh" "./script/process/quality-quick.sh" "quality-quick implementation"
assert_contains "source ./script/process/lib/quality-common.sh" "./script/process/quality-gate.sh" "quality-gate implementation"

set +e
PATH="$bin_dir:$PATH" /bin/bash ./script/process/check-solhint.sh "$existing_test_file" >"$check_solhint_output" 2>&1
check_solhint_status=$?
set -e
if [ "$check_solhint_status" -ne 0 ]; then
    echo "Expected check-solhint.sh to skip/pass when only ignored test Solidity files are selected"
    cat "$check_solhint_output"
    exit 1
fi

run_quality_script "quality-quick.sh" "script/process/check-coverage.js" "$quick_output"
assert_contains "[quality-quick] node --check (changed process JS files)" "$quick_output" "quality-quick output for process JS change"
assert_contains "run docs:check" "$npm_log" "quality-quick npm log for process JS change"
assert_contains "run process:selftest" "$npm_log" "quality-quick npm log for process JS change"

run_quality_script "quality-quick.sh" "script/process/fixtures/example.txt" "$quick_output"
assert_contains "run docs:check" "$npm_log" "quality-quick npm log for generic process surface change"
assert_contains "run process:selftest" "$npm_log" "quality-quick npm log for generic process surface change"

run_quality_script "quality-quick.sh" ".githooks/pre-commit" "$quick_output"
assert_contains "run docs:check" "$npm_log" "quality-quick npm log for githook change"

run_quality_script "quality-gate.sh" "docs/process/policy.json" "$gate_output"
assert_contains "run docs:check" "$npm_log" "quality-gate npm log for policy change"
assert_contains "run process:selftest" "$npm_log" "quality-gate npm log for policy change"
assert_contains "QUALITY_GATE_MODE= QUALITY_GATE_FILE_LIST= QUALITY_GATE_CHANGESET_FILE_LIST= CMD=run process:selftest" "$npm_log" "quality-gate npm log for sanitized process:selftest env"

run_quality_script "quality-gate.sh" ".githooks/pre-commit" "$gate_output"
assert_contains "run docs:check" "$npm_log" "quality-gate npm log for githook change"

run_quality_script "quality-gate.sh" "package.json" "$gate_output"
assert_contains "ci" "$npm_log" "quality-gate npm log for package change"
assert_contains "run docs:check" "$npm_log" "quality-gate npm log for package change"
assert_contains "run process:selftest" "$npm_log" "quality-gate npm log for package change"

run_quality_script "quality-quick.sh" "$existing_src_file" "$quick_output" "non-semantic" "diff --git a/$existing_src_file b/$existing_src_file
--- a/$existing_src_file
+++ b/$existing_src_file
@@ -1 +1 @@
-// old
+// new"
assert_contains "change classification: non-semantic" "$quick_output" "quality-quick output for non-semantic Solidity change"
assert_contains "bash ./script/process/check-solhint.sh" "$command_log" "quality-quick command log for non-semantic Solidity change"
assert_contains "forge fmt --check $existing_src_file" "$command_log" "quality-quick command log for non-semantic Solidity change"
assert_contains "forge build" "$command_log" "quality-quick command log for non-semantic Solidity change"

run_quality_script "quality-gate.sh" "$existing_src_file" "$gate_output" "non-semantic" "diff --git a/$existing_src_file b/$existing_src_file
--- a/$existing_src_file
+++ b/$existing_src_file
@@ -1 +1 @@
-// old
+// new"
assert_contains "change classification: non-semantic" "$gate_output" "quality-gate output for non-semantic Solidity change"
assert_contains "verifier profile: light" "$gate_output" "quality-gate output for non-semantic Solidity change"
assert_contains "bash ./script/process/check-solhint.sh" "$command_log" "quality-gate command log for non-semantic Solidity change"
assert_contains "forge fmt --check $existing_src_file" "$command_log" "quality-gate command log for non-semantic Solidity change"
assert_contains "forge build" "$command_log" "quality-gate command log for non-semantic Solidity change"
assert_contains "bash ./script/process/check-natspec.sh" "$command_log" "quality-gate command log for non-semantic Solidity change"
assert_contains "bash ./script/process/check-solidity-review-note.sh" "$command_log" "quality-gate command log for non-semantic Solidity change"
assert_contains "forge test -vvv" "$command_log" "quality-gate command log for non-semantic strict full suite"
if grep -q "check-slither" "$command_log"; then
    echo "Did not expect slither for non-semantic Solidity change"
    cat "$command_log"
    exit 1
fi

run_quality_script "quality-gate.sh" "$existing_test_file" "$gate_output" "test-semantic" "diff --git a/$existing_test_file b/$existing_test_file
--- a/$existing_test_file
+++ b/$existing_test_file
@@ -10 +10 @@
-        assertEq(result, 1);
+        assertEq(result, 2);"
assert_contains "change classification: test-semantic" "$gate_output" "quality-gate output for test-semantic Solidity change"
assert_contains "verifier profile: light" "$gate_output" "quality-gate output for test-semantic Solidity change"
assert_contains "forge test -vvv" "$command_log" "quality-gate command log for test-semantic change"
if grep -q "check-coverage" "$command_log"; then
    echo "Did not expect coverage for test-semantic change"
    cat "$command_log"
    exit 1
fi

run_quality_script "quality-gate.sh" "$existing_src_file" "$gate_output" "prod-semantic" "diff --git a/$existing_src_file b/$existing_src_file
--- a/$existing_src_file
+++ b/$existing_src_file
@@ -10 +10 @@
-        return amount;
+        return amount + 1;" "staged"
assert_contains "change classification: prod-semantic" "$gate_output" "quality-gate output for prod-semantic Solidity change"
assert_contains "verifier profile: full" "$gate_output" "quality-gate output for prod-semantic Solidity change"
assert_contains "forge test -vvv" "$command_log" "quality-gate command log for prod-semantic change"
assert_contains "bash ./script/process/check-coverage.sh" "$command_log" "quality-gate command log for prod-semantic change"
assert_contains "bash ./script/process/check-slither.sh" "$command_log" "quality-gate command log for prod-semantic change"
assert_contains "run codex:review" "$npm_log" "quality-gate npm log for staged prod-semantic change"

run_quality_script "quality-gate.sh" "$existing_script_file" "$gate_output" "prod-semantic" "diff --git a/$existing_script_file b/$existing_script_file
--- a/$existing_script_file
+++ b/$existing_script_file
@@ -10 +10 @@
-        return amount;
+        return amount + 1;" "staged"
assert_contains "change classification: prod-semantic" "$gate_output" "quality-gate output for script-only prod-semantic Solidity change"
assert_contains "verifier profile: full" "$gate_output" "quality-gate output for script-only prod-semantic Solidity change"
assert_contains "forge test -vvv" "$command_log" "quality-gate command log for script-only prod-semantic change"
assert_contains "bash ./script/process/check-coverage.sh" "$command_log" "quality-gate command log for script-only prod-semantic change"
assert_contains "skip slither (script Solidity surface; no src Solidity files in scope)" "$gate_output" "quality-gate output for script-only prod-semantic Solidity change"
if grep -q "check-slither" "$command_log"; then
    echo "Did not expect slither for script-only prod-semantic Solidity change"
    cat "$command_log"
    exit 1
fi
if grep -q "check-gas-report" "$command_log"; then
    echo "Did not expect gas report for script-only prod-semantic Solidity change"
    cat "$command_log"
    exit 1
fi
assert_contains "run codex:review" "$npm_log" "quality-gate npm log for staged script-only prod-semantic change"

run_quality_script "quality-quick.sh" "$created_spec_fixture" "$quick_output"
assert_contains "default roles: process-implementer; spec-reviewer; verifier" "$quick_output" "quality-quick output for spec surface change"
assert_contains "bash ./script/process/check-spec-reviewer-evidence.sh" "$command_log" "quality-quick command log for spec surface change"
assert_contains "run docs:check" "$npm_log" "quality-quick npm log for spec surface change"
assert_contains "run process:selftest" "$npm_log" "quality-quick npm log for spec surface change"

run_quality_script "quality-gate.sh" "$created_spec_fixture" "$gate_output"
assert_contains "default roles: process-implementer; spec-reviewer; verifier" "$gate_output" "quality-gate output for spec surface change"
assert_contains "bash ./script/process/check-spec-reviewer-evidence.sh" "$command_log" "quality-gate command log for spec surface change"
assert_contains "run docs:check" "$npm_log" "quality-gate npm log for spec surface change"
assert_contains "run process:selftest" "$npm_log" "quality-gate npm log for spec surface change"

run_quality_script "quality-quick.sh" "$created_spec_task_brief_fixture" "$quick_output"
assert_contains "default roles: process-implementer; spec-reviewer; verifier" "$quick_output" "quality-quick output for brief-declared spec surface change"
assert_contains "bash ./script/process/check-spec-reviewer-evidence.sh" "$command_log" "quality-quick command log for brief-declared spec surface change"
assert_contains "run docs:check" "$npm_log" "quality-quick npm log for brief-declared spec surface change"
assert_contains "run process:selftest" "$npm_log" "quality-quick npm log for brief-declared spec surface change"

run_quality_script "quality-gate.sh" "$created_spec_task_brief_fixture" "$gate_output"
assert_contains "default roles: process-implementer; spec-reviewer; verifier" "$gate_output" "quality-gate output for brief-declared spec surface change"
assert_contains "bash ./script/process/check-spec-reviewer-evidence.sh" "$command_log" "quality-gate command log for brief-declared spec surface change"
assert_contains "run docs:check" "$npm_log" "quality-gate npm log for brief-declared spec surface change"
assert_contains "run process:selftest" "$npm_log" "quality-gate npm log for brief-declared spec surface change"

run_quality_script "quality-gate.sh" "$existing_src_file" "$gate_output" "prod-semantic" "diff --git a/$existing_src_file b/$existing_src_file
--- a/$existing_src_file
+++ b/$existing_src_file
@@ -10 +10 @@
-        return amount;
+        return amount + 1;"
if grep -q "run codex:review" "$npm_log"; then
    echo "Did not expect codex review for ci-mode quality-gate"
    cat "$npm_log"
    exit 1
fi

: > "$wrapper_log"
printf '%s\n' "$existing_src_file" > "$changed_files_path"
PATH="$bin_dir:$PATH" QUALITY_GATE_FILE_LIST="$changed_files_path" /bin/bash ./script/process/run-quality-gate-full.sh
assert_contains "QUALITY_GATE_MODE=ci" "$wrapper_log" "run-quality-gate-full wrapper log"
if [ ! -f "$wrapper_file_list" ]; then
    echo "Expected run-quality-gate-full.sh to pass a file list to quality-gate.sh"
    cat "$wrapper_log"
    exit 1
fi
if [ ! -f "$wrapper_changeset_file_list" ]; then
    echo "Expected run-quality-gate-full.sh to pass a workflow changeset file to quality-gate.sh"
    cat "$wrapper_log"
    exit 1
fi
if ! grep -qxF "$existing_src_file" "$wrapper_changeset_file_list"; then
    echo "Expected run-quality-gate-full.sh to preserve caller-provided QUALITY_GATE_CHANGESET_FILE_LIST semantics"
    cat "$wrapper_changeset_file_list"
    exit 1
fi
if ! grep -qxF "$existing_src_file" "$wrapper_file_list"; then
    echo "Expected run-quality-gate-full.sh full-scan file list to still cover repo files including the explicit changeset path"
    cat "$wrapper_file_list"
    exit 1
fi
if [ "$(wc -l < "$wrapper_file_list")" -le 1 ]; then
    echo "Expected run-quality-gate-full.sh to keep a broader full-gate file list instead of narrowing to the caller changeset"
    cat "$wrapper_file_list"
    exit 1
fi

echo "quality-gates selftest: PASS"
