#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

for path in \
    ".codex/templates/task-brief.md" \
    ".codex/templates/role-delta-brief.md" \
    ".codex/templates/follow-up-brief.md"
do
    if [ ! -f "$path" ]; then
        echo "Expected brief template missing: $path"
        exit 1
    fi
done

if ! grep -q '^- Change classification:' .codex/templates/task-brief.md; then
    echo "Expected Task Brief template to require Change classification"
    exit 1
fi

if ! grep -q '^- Change classification rationale:' .codex/templates/task-brief.md; then
    echo "Expected Task Brief template to require Change classification rationale"
    exit 1
fi

if ! grep -q '^- Out of scope:' .codex/templates/task-brief.md; then
    echo "Expected Task Brief template to require Out of scope"
    exit 1
fi

if ! grep -q '^- Known facts:' .codex/templates/task-brief.md; then
    echo "Expected Task Brief template to require Known facts"
    exit 1
fi

if ! grep -q '^- Open questions / assumptions:' .codex/templates/task-brief.md; then
    echo "Expected Task Brief template to require Open questions / assumptions"
    exit 1
fi

if ! grep -q '^- If blocked:' .codex/templates/task-brief.md; then
    echo "Expected Task Brief template to require If blocked"
    exit 1
fi

if ! grep -q '^- Verifier profile:' .codex/templates/task-brief.md; then
    echo "Expected Task Brief template to require Verifier profile"
    exit 1
fi

if ! grep -q '^## Spec Surface（追加 3 字段）' .codex/templates/task-brief.md; then
    echo "Expected Task Brief template to include a dedicated Spec Surface section"
    exit 1
fi

for required_field in \
    '- Artifact type:' \
    '- Spec review required:' \
    '- Spec artifact paths:'
do
    if ! grep -qF -- "$required_field" .codex/templates/task-brief.md; then
        echo "Expected Task Brief template to require ${required_field#^- }"
        exit 1
    fi
    if ! grep -qF -- "$required_field" .codex/templates/follow-up-brief.md; then
        echo "Expected Follow-up Brief template to require ${required_field#^- }"
        exit 1
    fi
done

for spec_field in \
    '- Artifact type:' \
    '- Spec review required:' \
    '- Spec artifact paths:'
do
    if ! grep -qF -- "$spec_field" .codex/templates/task-brief.md; then
        echo "Expected Task Brief template to retain ${spec_field#^- } for the spec surface"
        exit 1
    fi
done

if ! grep -q '^- Parent Task Brief path:' .codex/templates/role-delta-brief.md; then
    echo "Expected Role Delta Brief template to reference the parent task brief"
    exit 1
fi

if ! grep -q '^- Target role:' .codex/templates/role-delta-brief.md; then
    echo "Expected Role Delta Brief template to require a target role"
    exit 1
fi

if ! grep -q '^- Parent Task Brief path:' .codex/templates/follow-up-brief.md; then
    echo "Expected Follow-up Brief template to reference the parent task brief"
    exit 1
fi

if ! grep -q '^- Trigger artifact:' .codex/templates/follow-up-brief.md; then
    echo "Expected Follow-up Brief template to require Trigger artifact"
    exit 1
fi

if ! grep -q '^- Trigger stale findings:' .codex/templates/follow-up-brief.md; then
    echo "Expected Follow-up Brief template to require Trigger stale findings"
    exit 1
fi

if ! grep -q '^- Required rerun roles:' .codex/templates/follow-up-brief.md; then
    echo "Expected Follow-up Brief template to require rerun roles"
    exit 1
fi

if ! grep -q 'role_delta_brief_template' docs/process/policy.json; then
    echo "Expected policy to declare role_delta_brief_template"
    exit 1
fi

if ! grep -q 'follow_up_brief_template' docs/process/policy.json; then
    echo "Expected policy to declare follow_up_brief_template"
    exit 1
fi

if ! grep -q 'Role Delta Brief' AGENTS.md; then
    echo "Expected AGENTS.md to describe Role Delta Brief usage"
    exit 1
fi

echo "brief-templates selftest: PASS"
