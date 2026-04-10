#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

files=()

if [ "$#" -gt 0 ]; then
    for file in "$@"; do
        [ -f "$file" ] || continue
        files+=("$file")
    done
else
    while IFS= read -r file; do
        [ -n "$file" ] || continue
        files+=("$file")
    done < <(rg --files src test -g '*.sol')
fi

if [ "${#files[@]}" -eq 0 ]; then
    echo "[check-solhint] no Solidity files selected, skipping."
    exit 0
fi

echo "[check-solhint] linting ${#files[@]} Solidity file(s)"
set +e
solhint_output="$(npx solhint --disc --noPoster "${files[@]}" 2>&1)"
solhint_status=$?
set -e

if [ "$solhint_status" -eq 0 ]; then
    if [ -n "$solhint_output" ]; then
        printf '%s\n' "$solhint_output"
    fi
    exit 0
fi

if printf '%s\n' "$solhint_output" | grep -q "No files to lint!"; then
    echo "[check-solhint] selected files are ignored by .solhintignore, skipping."
    exit 0
fi

printf '%s\n' "$solhint_output" >&2
exit "$solhint_status"
