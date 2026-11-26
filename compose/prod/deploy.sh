#!/usr/bin/env bash
set -euo pipefail

readonly SOPS_IMAGE="ghcr.io/getsops/sops:v3.13.3-alpine"
readonly AGE_KEY_FILE="${AGE_KEY_FILE:-${HOME}/.config/sops/age/keys.txt}"

stack_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_dir="$(git -C "$stack_dir" rev-parse --show-toplevel)"
decrypted_env="$(mktemp "${XDG_RUNTIME_DIR:-/dev/shm}/wortlaut-env.XXXXXX")"
trap 'rm -f "$decrypted_env"' EXIT

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

git -C "$repository_dir" pull --ff-only
decrypt_secrets > "$decrypted_env"
compose pull
compose up --detach --remove-orphans
docker image prune --force >/dev/null
compose ps
