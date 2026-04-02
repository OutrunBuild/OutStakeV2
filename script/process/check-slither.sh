#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

slither_bin="${SLITHER_BIN:-slither}"
filter_paths="$(node ./script/process/read-process-config.js policy quality_gate.slither_filter_paths)"
exclude_detectors="$(node ./script/process/read-process-config.js policy quality_gate.slither_exclude_detectors)"
targets=("$@")

if [ "${#targets[@]}" -eq 0 ]; then
    if [ ! -d "src" ]; then
        echo "[check-slither] ERROR: default source directory not found: src"
        exit 1
    fi

    targets=("src")
fi

if ! command -v "$slither_bin" >/dev/null 2>&1; then
    echo "[check-slither] ERROR: slither not found in PATH"
    exit 1
fi

echo "[check-slither] INFO: running slither"

for target in "${targets[@]}"; do
    echo "[check-slither] INFO: target=$target"
    "$slither_bin" "$target" \
        --filter-paths "$filter_paths" \
        --exclude-dependencies \
        --exclude "$exclude_detectors"
done
