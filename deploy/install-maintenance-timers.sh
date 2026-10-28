#!/bin/sh
set -eu

release_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
unit_directory=${LEAVE_DESK_SYSTEMD_DIRECTORY:-/etc/systemd/system}
backup_service=leave-desk-backup.service
backup_timer=leave-desk-backup.timer
cache_service=leave-desk-cache-cleanup.service
cache_timer=leave-desk-cache-cleanup.timer

for unit in "$backup_service" "$backup_timer" "$cache_service" "$cache_timer"; do
  install -m 0644 "$release_directory/$unit" "$unit_directory/$unit"
  if ! cmp -s "$release_directory/$unit" "$unit_directory/$unit"; then
    echo "Installed unit differs from release: $unit" >&2
    exit 1
  fi
done

systemctl daemon-reload
for timer in "$backup_timer" "$cache_timer"; do
  systemctl enable --now "$timer"
  systemctl restart "$timer"
  systemctl is-enabled --quiet "$timer"
  systemctl is-active --quiet "$timer"
done

for unit in "$backup_service" "$backup_timer" "$cache_service" "$cache_timer"; do
  fragment=$(systemctl show "$unit" -p FragmentPath --value)
  if [ "$fragment" != "$unit_directory/$unit" ]; then
    echo "Unexpected systemd unit path for $unit" >&2
    exit 1
  fi
done

systemctl start "$cache_service"
result=$(systemctl show "$cache_service" -p Result --value)
status=$(systemctl show "$cache_service" -p ExecMainStatus --value)
if [ "$result" != success ] || [ "$status" != 0 ]; then
  echo "Cache cleanup trial run failed" >&2
  exit 1
fi

echo "Backup and cache cleanup timers active; cache cleanup trial run succeeded"
