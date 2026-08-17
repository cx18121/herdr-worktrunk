#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT

mkdir -p "$sandbox/bin" "$sandbox/config" "$sandbox/repo"
cd "$sandbox/repo"
git init -q
git config user.email test@example.com
git config user.name test
git commit -q --allow-empty -m init
git branch automation/ticket-14-outbound-shipping

cat > "$sandbox/bin/fzf" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$FZF_ARGS_FILE"
cat >/dev/null
cat "$FZF_OUTPUT_FILE"
EOF

cat > "$sandbox/bin/wt" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$WT_CALL_FILE"
printf '{"path":"%s"}\n' "$WORKTREE_PATH"
EOF

cat > "$sandbox/bin/herdr" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  'worktree list')
    printf '{"result":{"source":{"source_workspace_id":"w-root"}}}\n'
    ;;
  'worktree open')
    printf '{"ok":true}\n'
    ;;
  *)
    printf 'unexpected herdr call: %s\n' "$*" >&2
    exit 1
    ;;
esac
EOF

chmod +x "$sandbox/bin/fzf" "$sandbox/bin/wt" "$sandbox/bin/herdr"
printf 'open_mode = "workspace"\nshow_remote_branches = false\n' > "$sandbox/config/config.toml"

export HERDR_PLUGIN_ROOT=$repo_root
export HERDR_PLUGIN_CONFIG_DIR=$sandbox/config
export HERDR_BIN_PATH=$sandbox/bin/herdr
export HERDR_WORKSPACE_ID=w-current
export PATH="$sandbox/bin:$PATH"
export FZF_ARGS_FILE=$sandbox/fzf-args
export FZF_OUTPUT_FILE=$sandbox/fzf-output
export WT_CALL_FILE=$sandbox/wt-call
export WORKTREE_PATH=$sandbox/worktree

assert_picker_call() {
  local picker_output=$1 expected=$2 actual

  printf '%s' "$picker_output" > "$FZF_OUTPUT_FILE"
  bash "$repo_root/picker.sh" --create-base=default >/dev/null
  actual=$(cat "$WT_CALL_FILE")
  if [[ $actual != "$expected" ]]; then
    printf 'expected picker call %q, got %q\n' "$expected" "$actual" >&2
    exit 1
  fi
}

assert_picker_call \
  $'pan-287\nopen\tautomation/ticket-14-outbound-shipping\n' \
  'switch --create pan-287 --no-cd --format=json'
assert_picker_call \
  $'automation/ticket-14-outbound-shipping\nopen\tautomation/ticket-14-outbound-shipping\n' \
  'switch automation/ticket-14-outbound-shipping --no-cd --format=json'
assert_picker_call \
  $'\nopen\tautomation/ticket-14-outbound-shipping\n' \
  'switch automation/ticket-14-outbound-shipping --no-cd --format=json'

fzf_args=" $(cat "$FZF_ARGS_FILE") "
if [[ $fzf_args != *' --exact '* ]]; then
  printf 'expected picker to enable exact fzf matching, got %q\n' "$fzf_args" >&2
  exit 1
fi

printf 'picker tests passed\n'
