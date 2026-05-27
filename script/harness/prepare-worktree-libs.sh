#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
script_root="$(cd "$script_dir/../.." && pwd -P)"

case "$script_root" in
    */.worktrees/*)
        canonical_root="${script_root%%/.worktrees/*}"
        ;;
    *)
        canonical_root="$script_root"
        ;;
esac

current_root="$(git rev-parse --show-toplevel)"
canonical_lib="$canonical_root/lib"

if [ "$current_root" = "$canonical_root" ]; then
    echo "canonical worktree: lib already local"
    exit 0
fi

case "$current_root" in
    "$canonical_root"/.worktrees/*)
        ;;
    *)
        echo "blocked: current worktree is not under $canonical_root/.worktrees"
        exit 1
        ;;
esac

expected_dependencies=(
    ds-test
    forge-std
    openzeppelin-contracts-upgradeable
    solmate
    solidity-bytes-utils
    layerzerolabs/devtools
    layerzerolabs/lz-evm-protocol-v2
)

for dependency in "${expected_dependencies[@]}"; do
    if [ ! -d "$canonical_lib/$dependency" ]; then
        echo "blocked: missing $canonical_lib/$dependency; prepare canonical dependencies first"
        exit 1
    fi
done

dependency_status="$(git -C "$current_root" status --short -- .gitmodules lib)"
if [ -n "$dependency_status" ]; then
    echo "blocked: dependency paths are dirty in this worktree"
    exit 1
fi

for dependency in "${expected_dependencies[@]}"; do
    current_dependency="$current_root/lib/$dependency"
    canonical_dependency="$canonical_lib/$dependency"

    if [ -L "$current_dependency" ]; then
        linked_target="$(readlink "$current_dependency")"
        if [ "$linked_target" = "$canonical_dependency" ]; then
            continue
        fi

        echo "blocked: existing $current_dependency symlink points to $linked_target"
        exit 1
    fi

    if [ -e "$current_dependency" ] && find "$current_dependency" -mindepth 1 -print -quit | grep -q .; then
        echo "blocked: existing $current_dependency is non-empty; not deleting automatically"
        exit 1
    fi

    rm -rf "$current_dependency"
    mkdir -p "$(dirname "$current_dependency")"
    ln -s "$canonical_dependency" "$current_dependency"
done

echo "linked worktree submodule libs to canonical lib"
