#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

readonly WAIT_TIMEOUT_SECONDS=420
readonly DEPLOYED_REVISION_FILE="$STATE_DIR/deployed-revision"
readonly SYNC_TIMER_INSTALLER="$repository_dir/host/install-sync-timer.sh"
deploying=no

service_states() {
  compose ps --all --format '{{.Service}}={{.State}}{{if .Health}}/{{.Health}}{{end}}' 2>/dev/null | tr '\n' ' ' || true
}

remove_unused_images() {
  local keep
  keep="$(compose --profile '*' config --images; echo "$SOPS_IMAGE")"
  docker image prune --force > /dev/null
  docker image ls --format '{{.Repository}}:{{.Tag}}'     | grep -vxF "$keep"     | xargs --no-run-if-empty docker image rm > /dev/null 2>&1 || true
}

report_result() {
  local status="$1" result=success message="deployed"
  if [[ "$status" -ne 0 ]]; then
    result=failure
    message="failed with exit status $status"
  fi
  "$stack_dir/report-status.sh" "$revision" "$result" "$message" "$(service_states)"
}

finish() {
  local status=$?
  if [[ "$deploying" == yes ]]; then
    report_result "$status" || echo "The deployment result could not be reported." >&2
  fi
  rm -f "$decrypted_env"
}
trap finish EXIT

git -C "$repository_dir" pull --ff-only
revision="$(git -C "$repository_dir" rev-parse HEAD)"
if [[ "${1:-}" != "--force" && "$(cat "$DEPLOYED_REVISION_FILE" 2>/dev/null || true)" == "$revision" ]]; then
  echo "Revision $revision is already deployed."
  exit 0
fi

deploying=yes
decrypt_secrets > "$decrypted_env"
compose pull
compose up --detach --remove-orphans --wait --wait-timeout "$WAIT_TIMEOUT_SECONDS"
compose run --rm --no-deps --no-TTY elasticsearch-setup
compose --profile jobs run --rm --no-deps --no-TTY kibana-setup || echo "The Kibana dashboards could not be imported." >&2
remove_unused_images
compose ps

mkdir -p "$STATE_DIR"
echo "$revision" > "$DEPLOYED_REVISION_FILE"

"$SYNC_TIMER_INSTALLER" || echo "The sync timer could not be installed." >&2
