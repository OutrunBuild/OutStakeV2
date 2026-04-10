#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

for path in \
    ".codex/agents/spec-reviewer.toml" \
    ".codex/agents/spec-reviewer.md" \
    ".claude/agents/spec-reviewer.md" \
    ".claude/rules/spec-surface.md"
do
    if [ ! -f "$path" ]; then
        echo "Expected spec-reviewer contract file missing: $path"
        exit 1
    fi
done

if ! grep -q '`spec-reviewer`' AGENTS.md; then
    echo "Expected AGENTS.md to mention spec-reviewer"
    exit 1
fi

if ! grep -q 'Phase 4: Spec Review' AGENTS.md; then
    echo "Expected AGENTS.md to define a dedicated Spec Review phase"
    exit 1
fi

if ! grep -q 'writer 先产出 spec，再由 `spec-reviewer` 审阅' AGENTS.md; then
    echo "Expected AGENTS.md to describe spec-reviewer as the spec review step"
    exit 1
fi

if ! grep -q 'docs/spec/\*\*' AGENTS.md; then
    echo "Expected AGENTS.md to list docs/spec/** as spec surface"
    exit 1
fi

if ! grep -q 'docs/superpowers/specs/\*\*' AGENTS.md; then
    echo "Expected AGENTS.md to list docs/superpowers/specs/** as spec surface"
    exit 1
fi

if ! grep -q 'spec review evidence' AGENTS.md; then
    echo "Expected AGENTS.md to reference spec review evidence"
    exit 1
fi

if ! grep -q 'Artifact type: spec' docs/process/change-matrix.md; then
    echo "Expected docs/process/change-matrix.md to bind Artifact type: spec to the spec surface"
    exit 1
fi

if ! grep -q '`process-implementer` → `spec-reviewer` → `verifier`' docs/process/change-matrix.md; then
    echo "Expected docs/process/change-matrix.md to keep spec surface dispatch order"
    exit 1
fi

echo "spec-reviewer-contract selftest: PASS"
