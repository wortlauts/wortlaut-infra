#!/usr/bin/env bash
# Tests sync.sh and install-sync-timer.sh against fake docker and systemctl commands.
set -euo pipefail

repository_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

export XDG_CONFIG_HOME="$work_dir/config"
export XDG_STATE_HOME="$work_dir/state"
export XDG_RUNTIME_DIR="$work_dir/run"
export PATH="$work_dir/bin:$PATH"
export FAKE_LOG="$work_dir/commands.log"
mkdir -p "$XDG_RUNTIME_DIR" "$work_dir/bin"

cat > "$work_dir/bin/docker" <<'FAKE'
#!/usr/bin/env bash
echo "docker $*" >> "$FAKE_LOG"
if [[ "$*" == *compose*" run "* ]]; then
  if [[ -n "${FAKE_SYNC_FAILS:-}" ]]; then
    echo "1 of 3 protocols could not be synchronised." >&2
    exit 1
  fi
  echo "21/112: 5 of 5 speeches written (5 new, 0 updated), 0 removed"
  echo "Done: 3 protocols checked, 5 speeches written (5 new, 0 updated), 0 removed, 0 failed"
fi
FAKE
cat > "$work_dir/bin/systemctl" <<'FAKE'
#!/usr/bin/env bash
echo "systemctl $*" >> "$FAKE_LOG"
FAKE
chmod +x "$work_dir/bin/docker" "$work_dir/bin/systemctl"

failures=0

check() {
  local description="$1"
  shift
  if "$@"; then
    echo "ok     $description"
  else
    echo "FAILED $description"
    failures=$((failures + 1))
  fi
}

not() { ! "$@"; }
log_contains() { grep -q -- "$1" "$FAKE_LOG"; }
log_lacks() { ! grep -q -- "$1" "$FAKE_LOG"; }
status_contains() { grep -qx -- "$1" "$XDG_STATE_HOME/wortlaut/sync-status.env"; }

: > "$FAKE_LOG"
"$repository_dir/compose/prod/sync.sh" > /dev/null
check "a successful sync pulls the indexer image" log_contains "pull --quiet indexer"
check "a successful sync runs the sync command without starting dependencies" log_contains "run --rm --no-TTY --no-deps indexer sync"
check "a successful sync is recorded as success" status_contains "result=success"
check "the summary of the sync is recorded" status_contains "summary=Done: 3 protocols checked, 5 speeches written (5 new, 0 updated), 0 removed, 0 failed"
check "the decrypted secrets are removed afterwards" test -z "$(ls -A "$XDG_RUNTIME_DIR")"

if FAKE_SYNC_FAILS=yes "$repository_dir/compose/prod/sync.sh" > /dev/null 2>&1; then
  sync_failed=no
else
  sync_failed=yes
fi
check "a failing sync fails the script" test "$sync_failed" = yes
check "a failing sync is recorded as failure" status_contains "result=failure"

: > "$FAKE_LOG"
"$repository_dir/host/install-sync-timer.sh"
unit_dir="$XDG_CONFIG_HOME/systemd/user"
check "the service unit points to the sync script of this checkout" grep -qx "ExecStart=$repository_dir/compose/prod/sync.sh" "$unit_dir/wortlaut-sync.service"
check "no placeholder is left in the installed service unit" not grep -q '@STACK_DIR@' "$unit_dir/wortlaut-sync.service"
check "the first installation reloads systemd and enables the timer" log_contains "systemctl --user daemon-reload"
check "the timer is enabled and started" log_contains "systemctl --user enable --now wortlaut-sync.timer"

: > "$FAKE_LOG"
"$repository_dir/host/install-sync-timer.sh"
check "installing again does not reload systemd" log_lacks "daemon-reload"

exit "$failures"
