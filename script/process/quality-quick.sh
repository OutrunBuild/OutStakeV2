#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

mode="${QUALITY_GATE_MODE:-staged}"

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

if [ "$mode" = "ci" ]; then
    changed_files="$(load_file_list_from_ci)"
else
    changed_files="$(git diff --cached --name-only --diff-filter=ACMRD)"
fi

if [ -z "$changed_files" ]; then
    echo "[quality-quick] no files to check, skipping."
    exit 0
fi

src_sol_pattern="$(node ./script/process/read-process-config.js policy quality_gate.src_sol_pattern)"
script_sol_pattern="$(node ./script/process/read-process-config.js policy quality_gate.script_sol_pattern 2>/dev/null || printf '%s' '^script/.*\.sol$')"
test_tsol_pattern="$(node ./script/process/read-process-config.js policy quality_gate.test_tsol_pattern)"
test_sol_pattern="$(node ./script/process/read-process-config.js policy quality_gate.test_sol_pattern)"
shell_pattern="$(node ./script/process/read-process-config.js policy quality_gate.shell_pattern)"
process_surface_pattern="$(node ./script/process/read-process-config.js policy quality_gate.process_surface_pattern)"
process_js_pattern="$(node ./script/process/read-process-config.js policy quality_gate.process_js_pattern)"
package_pattern="$(node ./script/process/read-process-config.js policy quality_gate.package_pattern)"
docs_contract_pattern="$(node ./script/process/read-process-config.js policy quality_gate.docs_contract_pattern)"
mapfile -t process_selftest_patterns < <(node ./script/process/read-process-config.js policy quality_gate.process_selftest_patterns --lines)
mapfile -t src_default_roles < <(node ./script/process/read-process-config.js policy quality_gate.src_default_roles --lines)
mapfile -t src_optional_roles < <(node ./script/process/read-process-config.js policy quality_gate.src_optional_roles --lines)
mapfile -t test_default_roles < <(node ./script/process/read-process-config.js policy quality_gate.test_default_roles --lines)
mapfile -t test_optional_roles < <(node ./script/process/read-process-config.js policy quality_gate.test_optional_roles --lines)
mapfile -t process_default_roles < <(node ./script/process/read-process-config.js policy quality_gate.process_default_roles --lines)
mapfile -t package_default_roles < <(node ./script/process/read-process-config.js policy quality_gate.package_default_roles --lines)
mapfile -t docs_contract_default_roles < <(node ./script/process/read-process-config.js policy quality_gate.docs_contract_default_roles --lines)
classification_json="$(QUALITY_GATE_MODE="$mode" QUALITY_GATE_FILE_LIST="${QUALITY_GATE_FILE_LIST:-}" CHANGE_CLASSIFIER_DIFF_FILE="${CHANGE_CLASSIFIER_DIFF_FILE:-}" node ./script/process/classify-change.js)"

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

has_src_sol=0
has_script_sol=0
has_sol_tests=0
has_package_metadata=0
has_docs_contract=0
has_process_surface=0
should_run_docs_check=0
should_run_process_selftest=0
src_solidity_candidates=()
test_solidity_candidates=()
solidity_files=()
src_solidity_files=()
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
        src_solidity_candidates+=("$file")
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

for file in "${src_solidity_candidates[@]}" "${test_solidity_candidates[@]}"; do
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

if [ "$has_src_sol" -eq 1 ] || [ "$has_script_sol" -eq 1 ] || [ "$has_sol_tests" -eq 1 ]; then
    echo "[quality-quick] change classification: $classification"
    echo "[quality-quick] classification rationale: $classification_rationale"
    echo "[quality-quick] default roles: $(join_by_semicolon "solidity-implementer" "${classifier_required_roles[@]}")"
    echo "[quality-quick] optional roles: $(join_by_semicolon "${classifier_optional_roles[@]}")"
    echo "[quality-quick] verifier profile: $verifier_profile"

    if [ "${#solidity_files[@]}" -gt 0 ]; then
        echo "[quality-quick] forge fmt --check (changed Solidity files only)"
        forge fmt --check "${solidity_files[@]}"
    fi

    if [ "$has_src_sol" -eq 1 ] && [ "${#src_solidity_files[@]}" -gt 0 ]; then
        echo "[quality-quick] bash ./script/process/check-natspec.sh (changed src Solidity files only)"
        bash ./script/process/check-natspec.sh "${src_solidity_files[@]}"
    fi

    echo "[quality-quick] forge build"
    forge build

    case "$classification" in
        non-semantic)
            echo "[quality-quick] skip Solidity tests (non-semantic classification)"
            ;;
        test-semantic)
            targeted_tests=()
            for file in "${changed_test_files[@]}"; do
                if [ -f "$file" ]; then
                    targeted_tests+=("$file")
                fi
            done

            if [ "${#targeted_tests[@]}" -gt 0 ]; then
                mapfile -t deduped_targeted_tests < <(printf '%s\n' "${targeted_tests[@]}" | awk '!seen[$0]++')
                for test_file in "${deduped_targeted_tests[@]}"; do
                    echo "[quality-quick] forge test --match-path $test_file"
                    forge test --match-path "$test_file"
                done
            elif [ "$has_sol_tests" -eq 1 ]; then
                echo "[quality-quick] forge test"
                forge test
            else
                echo "[quality-quick] no targeted Solidity tests selected."
            fi
            ;;
        prod-semantic|high-risk)
            echo "[quality-quick] forge test -vvv"
            forge test -vvv
            ;;
        *)
            echo "[quality-quick] skip Solidity tests (classification '$classification')"
            ;;
    esac
fi

if [ "$has_process_surface" -eq 1 ]; then
    echo "[quality-quick] default roles: $(join_by_semicolon "${process_default_roles[@]}")"
fi

if [ "${#shell_files[@]}" -gt 0 ]; then
    echo "[quality-quick] bash -n (changed shell scripts)"
    bash -n "${shell_files[@]}"
fi

if [ "${#process_js_files[@]}" -gt 0 ]; then
    echo "[quality-quick] node --check (changed process JS files)"
    node --check "${process_js_files[@]}"
fi

if [ "$has_package_metadata" -eq 1 ]; then
    echo "[quality-quick] default roles: $(join_by_semicolon "${package_default_roles[@]}")"
    echo "[quality-quick] npm ci"
    npm ci
fi

if [ "$should_run_docs_check" -eq 1 ]; then
    if [ "$has_docs_contract" -eq 1 ] && [ "$has_process_surface" -eq 0 ] && [ "$has_package_metadata" -eq 0 ]; then
        echo "[quality-quick] default roles: $(join_by_semicolon "${docs_contract_default_roles[@]}")"
    fi
    echo "[quality-quick] npm run docs:check"
    npm run docs:check
fi

if [ "$should_run_process_selftest" -eq 1 ]; then
    if [ "$has_process_surface" -eq 0 ] && [ "$has_package_metadata" -eq 0 ]; then
        echo "[quality-quick] default roles: $(join_by_semicolon "${process_default_roles[@]}")"
    fi
    echo "[quality-quick] npm run process:selftest"
    npm run process:selftest
fi

echo "[quality-quick] PASS (quick only, final verification still requires npm run quality:gate)"
