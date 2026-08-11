#!/usr/bin/env bash
set -euo pipefail

hook_json=$(cat)
isolation=$(jq -r '.tool_input.isolation // empty' <<<"$hook_json")

if [[ "$isolation" == "worktree" ]]; then
  jq -n \
    --arg stopReason 'OutStakeV2 forbids Agent(isolation:"worktree") because Claude Code auto-creates .claude/worktrees/*. For isolated writes, first manually create a git worktree at .worktrees/<name>, then have the subagent cd into that absolute path. Read-only Agents should not set isolation.' \
    '{continue: false, stopReason: $stopReason}'
fi
