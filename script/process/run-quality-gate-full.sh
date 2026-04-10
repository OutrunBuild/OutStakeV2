#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

tmp_file_list="$(mktemp)"
changeset_file_list="$(mktemp)"
computed_file_list="$tmp_file_list"
computed_changeset_file_list="$changeset_file_list"

cleanup() {
    rm -f "$tmp_file_list"
    rm -f "$changeset_file_list"
}
trap cleanup EXIT

git ls-files > "$computed_file_list"

if [ -n "${QUALITY_GATE_CHANGESET_FILE_LIST:-}" ] && [ -f "${QUALITY_GATE_CHANGESET_FILE_LIST}" ]; then
    computed_changeset_file_list="${QUALITY_GATE_CHANGESET_FILE_LIST}"
elif [ -n "${QUALITY_GATE_FILE_LIST:-}" ] && [ -f "${QUALITY_GATE_FILE_LIST}" ]; then
    computed_changeset_file_list="${QUALITY_GATE_FILE_LIST}"
elif git rev-parse --verify '@{upstream}' >/dev/null 2>&1; then
    git diff --name-only '@{upstream}...HEAD' > "$computed_changeset_file_list"
elif git rev-parse --verify HEAD~1 >/dev/null 2>&1; then
    git diff --name-only HEAD~1..HEAD > "$computed_changeset_file_list"
else
    git ls-files > "$computed_changeset_file_list"
fi

QUALITY_GATE_MODE=ci \
QUALITY_GATE_FILE_LIST="$computed_file_list" \
QUALITY_GATE_CHANGESET_FILE_LIST="$computed_changeset_file_list" \
QUALITY_GATE_FAST=0 \
QUALITY_GATE_ERRORS_ONLY=1 \
QUALITY_GATE_HIDE_PASS=1 \
FORGE_TEST_VERBOSITY="${FORGE_TEST_VERBOSITY:--vvv}" \
bash ./script/process/quality-gate.sh
