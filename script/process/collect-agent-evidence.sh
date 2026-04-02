#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
    cat <<'EOF'
Usage: collect-agent-evidence.sh <agent-report> [agent-report ...]

Read one or more structured Agent Report markdown files and emit a unified
evidence summary that can be copied into a review note or troubleshooting log.
EOF
    exit 1
fi

extract_field() {
    local file="$1"
    local field="$2"

    awk -v field="$field" '
        index($0, "- " field ":") == 1 {
            value = substr($0, length("- " field ":") + 1)
            sub(/^ /, "", value)

            while (getline next_line > 0) {
                if (next_line ~ /^- [^:]+:/) {
                    break
                }

                if (next_line ~ /^  / || next_line ~ /^$/) {
                    value = value "\n" next_line
                    continue
                }

                break
            }

            print value
            exit
        }
    ' "$file"
}

reports=("$@")

printf '# Agent Evidence Summary\n\n'
printf -- '- Reports collected: %s\n' "${#reports[@]}"

for file in "${reports[@]}"; do
    if [ ! -f "$file" ]; then
        echo "[collect-agent-evidence] ERROR: report not found: $file" >&2
        exit 1
    fi

    role="$(extract_field "$file" "Role")"
    summary="$(extract_field "$file" "Summary")"
    touched="$(extract_field "$file" "Files touched/reviewed")"
    findings="$(extract_field "$file" "Findings")"
    follow_up="$(extract_field "$file" "Required follow-up")"
    commands="$(extract_field "$file" "Commands run")"
    evidence="$(extract_field "$file" "Evidence")"
    residual_risks="$(extract_field "$file" "Residual risks")"

    [ -z "$role" ] && role="unknown-role"
    [ -z "$summary" ] && summary="none"
    [ -z "$touched" ] && touched="none"
    [ -z "$findings" ] && findings="none"
    [ -z "$follow_up" ] && follow_up="none"
    [ -z "$commands" ] && commands="none"
    [ -z "$evidence" ] && evidence="none"
    [ -z "$residual_risks" ] && residual_risks="none"

    printf '\n## %s\n' "$role"
    printf -- '- Source file: %s\n' "$file"
    printf -- '- Summary: %s\n' "$summary"
    printf -- '- Files touched/reviewed: %s\n' "$touched"
    printf -- '- Findings: %s\n' "$findings"
    printf -- '- Required follow-up: %s\n' "$follow_up"
    printf -- '- Commands run: %s\n' "$commands"
    printf -- '- Evidence: %s\n' "$evidence"
    printf -- '- Residual risks: %s\n' "$residual_risks"
done
