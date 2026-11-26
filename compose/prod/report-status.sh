#!/usr/bin/env bash
# Records the result of a deployment as an info commit on the branch prod-status.
# Usage: report-status.sh <revision> <success|failure> <message> [services]
# Does nothing when no status key is installed, and never fails a deployment.
set -uo pipefail

readonly STATUS_BRANCH="prod-status"
readonly STATUS_KEY_FILE="${STATUS_KEY_FILE:-${HOME}/.ssh/wortlaut-status}"
readonly STATE_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}/wortlaut"

revision="$1"
result="$2"
message="$3"
services="${4:-}"

if [[ ! -f "$STATUS_KEY_FILE" ]]; then
  echo "No status key found, the result is not reported."
  exit 0
fi

stack_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
origin_url="$(git -C "$stack_dir" remote get-url origin)"
remote_url="${origin_url/https:\/\/github.com\//git@github.com:}"
status_dir="$STATE_DIR/status-repo"
export GIT_SSH_COMMAND="ssh -i $STATUS_KEY_FILE -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes"

publish() {
  mkdir -p "$STATE_DIR"
  if [[ ! -d "$status_dir/.git" ]]; then
    git clone --quiet --branch "$STATUS_BRANCH" --single-branch "$remote_url" "$status_dir"
  fi
  git -C "$status_dir" fetch --quiet origin "$STATUS_BRANCH"
  git -C "$status_dir" reset --quiet --hard "origin/$STATUS_BRANCH"

  cat > "$status_dir/status.env" <<STATUS
revision=$revision
result=$result
finished_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
message=${message//$'\n'/ }
services=${services//$'\n'/ }
STATUS

  git -C "$status_dir" add status.env
  git -C "$status_dir" -c user.name=wortlaut-deploy -c user.email=wortlaut-deploy@users.noreply.github.com \
    commit --quiet --message "Deployment of ${revision:0:7}: $result"
  git -C "$status_dir" push --quiet origin "$STATUS_BRANCH"
}

publish || echo "The deployment result could not be reported." >&2
