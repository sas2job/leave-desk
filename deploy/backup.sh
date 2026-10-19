#!/usr/bin/env bash
set -euo pipefail

umask 077
backup_directory=/var/backups/leave-desk
minimum_free_bytes=$((2 * 1024 * 1024 * 1024))
retention_seconds=$((7 * 24 * 60 * 60))

install -d -m 0700 -- "$backup_directory"
exec 9>"$backup_directory/.backup.lock"
flock -n 9 || { echo 'Backup is already running' >&2; exit 1; }

release_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
compose="$release_directory/compose.sh"
database_bytes=$("$compose" exec -T db psql -U leave_desk -d postgres -Atqc \
  "SELECT pg_database_size('leave_desk_production')")
[[ "$database_bytes" =~ ^[0-9]+$ ]] || { echo 'Could not measure database size' >&2; exit 1; }

available_bytes=$(df -B1 --output=avail "$backup_directory" | tail -n 1)
if (( available_bytes < minimum_free_bytes + 2 * database_bytes )); then
  echo 'Backup skipped: insufficient free space for dump and 2 GiB reserve' >&2
  exit 1
fi

timestamp=$(date -u +%Y%m%dT%H%M%SZ)
snapshot="$backup_directory/leave-desk-$timestamp"
[[ ! -e "$snapshot" ]] || { echo 'Backup for this second already exists' >&2; exit 1; }
staging=$(mktemp -d "$backup_directory/.incomplete.XXXXXXXX")
cleanup() {
  if [[ -d "$staging" ]]; then
    rm -f -- "$staging/database.dump" "$staging/database.dump.sha256"
    rmdir -- "$staging"
  fi
}
trap cleanup EXIT

"$compose" exec -T db pg_dump -U leave_desk --format=custom \
  --no-owner --no-privileges leave_desk_production > "$staging/database.dump"
"$compose" exec -T db pg_restore --list < "$staging/database.dump" > /dev/null
(cd "$staging" && sha256sum database.dump > database.dump.sha256)

available_bytes=$(df -B1 --output=avail "$backup_directory" | tail -n 1)
if (( available_bytes < minimum_free_bytes )); then
  echo 'Backup skipped: free space would fall below 2 GiB reserve' >&2
  exit 1
fi

mv -- "$staging" "$snapshot"
trap - EXIT
echo "Backup created: $snapshot"

now=$(date +%s)
for old_snapshot in "$backup_directory"/leave-desk-*; do
  [[ -d "$old_snapshot" ]] || continue
  [[ "${old_snapshot##*/}" =~ ^leave-desk-[0-9]{8}T[0-9]{6}Z$ ]] || continue
  age=$((now - $(stat -c %Y "$old_snapshot")))
  if (( age >= retention_seconds )); then
    rm -f -- "$old_snapshot/database.dump" "$old_snapshot/database.dump.sha256"
    rmdir -- "$old_snapshot"
    echo "Expired backup removed: $old_snapshot"
  fi
done
