#!/usr/bin/env bash
set -euo pipefail

readonly WORTLAUT_USER="wortlaut"
readonly MEMORY_MAX="${WORTLAUT_MEMORY_MAX:-2G}"
readonly BOOT_CMDLINE="/boot/firmware/cmdline.txt"

install_rootless_prerequisites() {
  apt-get update
  apt-get install -y uidmap slirp4netns dbus-user-session
}

delegate_cgroup_controllers() {
  install -d /etc/systemd/system/user@.service.d
  cat > /etc/systemd/system/user@.service.d/delegate.conf <<'EOF'
[Service]
Delegate=cpu cpuset io memory pids
EOF
  systemctl daemon-reload
}

enable_memory_cgroup() {
  if ! grep -q 'cgroup_disable=memory' "$BOOT_CMDLINE" && grep -q 'cgroup_enable=memory' "$BOOT_CMDLINE"; then
    echo "Memory cgroup is already enabled."
    return
  fi
  cp "$BOOT_CMDLINE" "$BOOT_CMDLINE.before-wortlaut"
  sed -i -e 's/cgroup_disable=memory//' -e 's/[[:space:]]*$//' "$BOOT_CMDLINE"
  sed -i -e 's/$/ cgroup_enable=memory cgroup_memory=1/' "$BOOT_CMDLINE"
  echo "Changed $BOOT_CMDLINE (backup: $BOOT_CMDLINE.before-wortlaut). Reboot to apply."
}

limit_memory_of_user() {
  local uid
  uid="$(id -u "$WORTLAUT_USER")"
  systemctl set-property "user-${uid}.slice" "MemoryMax=${MEMORY_MAX}"
  echo "Memory of all processes of $WORTLAUT_USER is limited to $MEMORY_MAX."
}

install_rootless_prerequisites
delegate_cgroup_controllers

if [[ "${1:-}" == "--memory-cgroup" ]]; then
  enable_memory_cgroup
  limit_memory_of_user
fi
