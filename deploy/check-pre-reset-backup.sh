#!/usr/bin/env bash
set -euo pipefail

backup_directory=${LEAVE_DESK_BACKUP_DIRECTORY:-/var/backups/leave-desk}
reset_cutoff=20261020T091700Z
latest=
latest_stamp=

for candidate in "$backup_directory"/leave-desk-*; do
  [[ -d "$candidate" ]] || continue
  name=${candidate##*/}
  [[ "$name" =~ ^leave-desk-([0-9]{8}T[0-9]{6}Z)$ ]] || continue
  stamp=${BASH_REMATCH[1]}
  [[ "$stamp" < "$reset_cutoff" ]] || continue
  if [[ -z "$latest" || "$stamp" > "$latest_stamp" ]]; then
    latest=$candidate
    latest_stamp=$stamp
  fi
done

if [[ -z "$latest" ]]; then
  echo 'Pre-reset backup: none retained'
  exit 0
fi

[[ -f "$latest/database.dump" && -f "$latest/database.dump.sha256" ]] || {
  echo 'Pre-reset backup is incomplete' >&2
  exit 1
}
(cd "$latest" && sha256sum --status --check database.dump.sha256) || {
  echo 'Pre-reset backup checksum failed' >&2
  exit 1
}

printf 'Pre-reset backup: %s; checksum: valid\n' "${latest##*/}"
