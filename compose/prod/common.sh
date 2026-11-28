# Shared by deploy.sh and sync.sh. Source this file, do not run it.
# The caller removes "$decrypted_env" when it is done, because the file holds the decrypted secrets.

readonly SOPS_IMAGE="ghcr.io/getsops/sops:v3.13.3-alpine"
readonly AGE_KEY_FILE="${AGE_KEY_FILE:-${HOME}/.config/sops/age/keys.txt}"
readonly STATE_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}/wortlaut"

stack_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_dir="$(git -C "$stack_dir" rev-parse --show-toplevel)"
decrypted_env="$(mktemp "${XDG_RUNTIME_DIR:-/dev/shm}/wortlaut-env.XXXXXX")"

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
