#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

forge_bin="${FORGE_BIN:-forge}"
node_bin="${NODE_BIN:-node}"
policy_file="${PROCESS_POLICY_FILE:-docs/process/policy.json}"
lcov_file="${COVERAGE_LCOV_FILE:-}"
normalized_lcov_file=""

cleanup() {
    if [ -n "$normalized_lcov_file" ] && [ -f "$normalized_lcov_file" ]; then
        rm -f "$normalized_lcov_file"
    fi
}

trap cleanup EXIT

usage() {
    cat <<'EOF'
Usage: check-coverage.sh [--lcov-file <path>] [--policy-file <path>] [--help]
EOF
}

normalize_lcov_branch_data() {
    local input_file="$1"
    local output_file="$2"

    "$node_bin" - "$input_file" "$output_file" <<'NODE'
const fs = require('fs');

const inputFile = process.argv[2];
const outputFile = process.argv[3];
const input = fs.readFileSync(inputFile, 'utf8');
const blocks = input.split('end_of_record');
let filteredBranches = 0;

const normalized = blocks
  .map((block) => {
    const trimmed = block.trim();
    if (!trimmed) {
      return '';
    }

    const lines = trimmed.split('\n');
    const outputLines = [];
    let branchFound = 0;
    let branchHit = 0;
    let sawBranchSection = false;

    for (const line of lines) {
      if (line.startsWith('BRDA:')) {
        sawBranchSection = true;
        const parts = line.slice(5).split(',');
        const taken = parts[3] || '-';
        if (taken === '-') {
          filteredBranches += 1;
          continue;
        }

        branchFound += 1;
        if (Number.parseInt(taken, 10) > 0) {
          branchHit += 1;
        }
        outputLines.push(line);
        continue;
      }

      if (line.startsWith('BRF:') || line.startsWith('BRH:')) {
        sawBranchSection = true;
        continue;
      }

      outputLines.push(line);
    }

    if (sawBranchSection) {
      outputLines.push(`BRF:${branchFound}`);
      outputLines.push(`BRH:${branchHit}`);
    }

    return `${outputLines.join('\n')}\nend_of_record\n`;
  })
  .join('');

fs.writeFileSync(outputFile, normalized);

if (filteredBranches > 0) {
  console.log(
    `[check-coverage] INFO: filtered ${filteredBranches} unresolved BRDA entries with taken='-' before threshold checks`
  );
} else {
  console.log('[check-coverage] INFO: no unresolved BRDA entries required filtering before threshold checks');
}
NODE
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --lcov-file)
            if [ "$#" -lt 2 ]; then
                echo "[check-coverage] ERROR: missing value for --lcov-file"
                exit 1
            fi
            lcov_file="$2"
            shift 2
            ;;
        --policy-file)
            if [ "$#" -lt 2 ]; then
                echo "[check-coverage] ERROR: missing value for --policy-file"
                exit 1
            fi
            policy_file="$2"
            shift 2
            ;;
        --help)
            usage
            "$node_bin" ./script/process/check-coverage.js --help
            exit 0
            ;;
        *)
            echo "[check-coverage] ERROR: unknown argument: $1"
            usage
            exit 1
            ;;
    esac
done

if [ -z "$lcov_file" ]; then
    lcov_file="$(PROCESS_POLICY_FILE="$policy_file" "$node_bin" ./script/process/read-process-config.js policy coverage.default_lcov_path)"
    report_dir="$(dirname "$lcov_file")"
    mkdir -p "$report_dir"

    echo "[check-coverage] INFO: running forge coverage with --ir-minimum"
    echo "[check-coverage] INFO: note=--ir-minimum improves stack-too-deep compatibility but may reduce source-map accuracy"
    "$forge_bin" coverage --ir-minimum --report summary --report lcov --report-file "$lcov_file"
else
    echo "[check-coverage] INFO: using existing lcov file: $lcov_file"
fi

if [ ! -s "$lcov_file" ]; then
    echo "[check-coverage] ERROR: lcov file not found or empty: $lcov_file"
    exit 1
fi

normalized_lcov_file="$(mktemp "${TMPDIR:-/tmp}/check-coverage.XXXXXX")"
normalize_lcov_branch_data "$lcov_file" "$normalized_lcov_file"

"$node_bin" ./script/process/check-coverage.js --policy-file "$policy_file" --lcov-file "$normalized_lcov_file"
