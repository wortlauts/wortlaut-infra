#!/usr/bin/env bash
# Installs and starts the systemd user timer that runs compose/prod/sync.sh every day.
# Run it as the user that runs the stack. It is safe to run repeatedly and is called by deploy.sh.
set -euo pipefail

readonly TIMER_UNIT="wortlaut-sync.timer"
readonly STACK_DIR_PLACEHOLDER="@STACK_DIR@"

host_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
stack_dir="$(cd "$host_dir/../compose/prod" && pwd)"
unit_dir="${XDG_CONFIG_HOME:-${HOME}/.config}/systemd/user"
state_dir="${XDG_STATE_HOME:-${HOME}/.local/state}/wortlaut"

# Succeeds only when the unit had to be written, so the caller knows that systemd must reload.
install_unit_if_changed() {
  local template="$1" target rendered
  target="$unit_dir/$(basename "$template")"
  rendered="$(sed "s|$STACK_DIR_PLACEHOLDER|$stack_dir|g" "$template")"
  if [[ "$(cat "$target" 2>/dev/null || true)" == "$rendered" ]]; then
    return 1
  fi
  printf '%s\n' "$rendered" > "$target"
}

mkdir -p "$unit_dir" "$state_dir"

units_changed=no
for template in "$host_dir"/systemd/wortlaut-sync.*; do
  if install_unit_if_changed "$template"; then
    units_changed=yes
  fi
done

if [[ "$units_changed" == yes ]]; then
  systemctl --user daemon-reload
fi
systemctl --user enable --now "$TIMER_UNIT"
