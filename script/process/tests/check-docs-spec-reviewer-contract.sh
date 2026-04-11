#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

for needle in \
    ".codex/agents/spec-reviewer.toml" \
    ".codex/agents/spec-reviewer.md" \
    ".claude/agents/spec-reviewer.md" \
    ".claude/rules/spec-surface.md" \
    "quality_gate.spec_default_roles" \
    "spec_surface" \
    "Artifact type" \
    "Spec review required" \
    "Spec artifact paths" \
    "docs/spec/**" \
    "docs/superpowers/specs/**" 
do
    if ! grep -qF "$needle" script/process/check-docs.sh docs/process/policy.json .codex/templates/task-brief.md .codex/templates/follow-up-brief.md 2>/dev/null; then
        echo "Expected check-docs spec-reviewer contract coverage for: $needle"
        exit 1
    fi
done

echo "check-docs-spec-reviewer-contract selftest: PASS"
