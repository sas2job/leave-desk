#!/usr/bin/env bash
set -euo pipefail

if (( $# != 0 )); then
  echo "Usage: backup-before-demo-correction.sh (no arguments)" >&2
  exit 64
fi

umask 077
cd /root/projects/leave-desk
compose=./current/compose.sh
backup_root=/var/backups/leave-desk
database_bytes=$("$compose" exec -T db psql -U leave_desk -d postgres -Atqc \
  "SELECT pg_database_size('leave_desk_production')" < /dev/null)
[[ "$database_bytes" =~ ^[0-9]+$ ]] || { echo 'Could not measure database size' >&2; exit 1; }
available_bytes=$(df -B1 --output=avail "$backup_root" | tail -n 1)
if (( available_bytes < 2 * 1024 * 1024 * 1024 + 2 * database_bytes )); then
  echo 'Insufficient free space for a correction backup' >&2
  exit 1
fi

snapshot=$(mktemp -d "$backup_root/demo-2026-before-correction-XXXXXXXX")
"$compose" exec -T db pg_dump -U leave_desk --format=custom \
  --no-owner --no-privileges leave_desk_production < /dev/null > "$snapshot/database.dump.incomplete"
"$compose" exec -T db pg_restore --list < "$snapshot/database.dump.incomplete" > /dev/null
mv -- "$snapshot/database.dump.incomplete" "$snapshot/database.dump"
(cd "$snapshot" && sha256sum database.dump > database.dump.sha256 && sha256sum -c database.dump.sha256)
printf 'Correction backup verified: %s\n' "$snapshot"
