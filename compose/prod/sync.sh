#!/usr/bin/env bash
# Imports the Bundestag protocols that are new or were corrected since the last run.
# Runs the sync command of the indexer image and records the result in the state directory.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

readonly SYNC_STATUS_FILE="$STATE_DIR/sync-status.env"

run_sync() {
  compose --profile jobs pull --quiet indexer
  compose --profile jobs run --rm --no-TTY --no-deps indexer sync
}

write_status() {
  local exit_status="$1" output="$2" result=success
  if [[ "$exit_status" -ne 0 ]]; then
    result=failure
  fi

  mkdir -p "$STATE_DIR"
  cat > "$SYNC_STATUS_FILE" <<STATUS
finished_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
result=$result
summary=$(grep '^Done:' <<< "$output" | tail -n 1 || true)
STATUS
}

trap 'rm -f "$decrypted_env"' EXIT

decrypt_secrets > "$decrypted_env"

sync_status=0
sync_output="$(run_sync 2>&1)" || sync_status=$?
echo "$sync_output"
write_status "$sync_status" "$sync_output"
exit "$sync_status"
