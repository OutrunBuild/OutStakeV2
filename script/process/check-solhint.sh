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
npx solhint --disc --noPoster "${files[@]}"
