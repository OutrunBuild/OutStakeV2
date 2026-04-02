#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

tmp_dir="$(mktemp -d)"
fake_bin_dir="$tmp_dir/bin"
codex_log="$tmp_dir/codex.log"
stderr_log="$tmp_dir/stderr.log"

cleanup() {
    rm -rf "$tmp_dir"
}
trap cleanup EXIT

mkdir -p "$fake_bin_dir"

cat > "$fake_bin_dir/codex" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$*" > "$codex_log"
EOF
chmod +x "$fake_bin_dir/codex"

PATH="$fake_bin_dir:$PATH" CODEX_REVIEW_BIN=codex bash ./script/process/run-codex-review.sh 2>"$stderr_log"

if ! grep -q "^review --uncommitted\( \|$\)" "$codex_log"; then
    echo "Expected run-codex-review.sh to invoke 'codex review --uncommitted'"
    cat "$codex_log"
    exit 1
fi

if grep -qi "logic bugs" "$codex_log"; then
    echo "Expected run-codex-review.sh to avoid passing a positional prompt with --uncommitted"
    cat "$codex_log"
    exit 1
fi

if grep -q "CODEX_REVIEW_PROMPT is ignored" "$stderr_log"; then
    echo "Expected run-codex-review.sh to stop mentioning ignored prompt state"
    cat "$stderr_log"
    exit 1
fi

echo "codex-review selftest: PASS"
