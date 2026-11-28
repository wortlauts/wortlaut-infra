#!/usr/bin/env bash
set -euo pipefail

readonly SOPS_IMAGE="ghcr.io/getsops/sops:v3.13.3-alpine"
readonly AGE_KEY_FILE="${AGE_KEY_FILE:-${HOME}/.config/sops/age/keys.txt}"
readonly WAIT_TIMEOUT_SECONDS=420
readonly DEPLOYED_REVISION_FILE="${XDG_STATE_HOME:-${HOME}/.local/state}/wortlaut/deployed-revision"

stack_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_dir="$(git -C "$stack_dir" rev-parse --show-toplevel)"
decrypted_env="$(mktemp "${XDG_RUNTIME_DIR:-/dev/shm}/wortlaut-env.XXXXXX")"
deploying=no

decrypt_secrets() {
  docker run --rm \
    -v "$AGE_KEY_FILE:/age/keys.txt:ro" \
    -e SOPS_AGE_KEY_FILE=/age/keys.txt \
    -v "$repository_dir:/repository:ro" \
    "$SOPS_IMAGE" decrypt --output-type dotenv "/repository/compose/prod/secrets/prod.enc.env"
}

compose() {
  docker compose --project-directory "$stack_dir" \
    --env-file "$stack_dir/versions.env" --env-file "$decrypted_env" "$@"
}

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
remove_unused_images
compose ps

mkdir -p "$(dirname "$DEPLOYED_REVISION_FILE")"
echo "$revision" > "$DEPLOYED_REVISION_FILE"
