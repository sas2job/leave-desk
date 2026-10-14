#!/usr/bin/env bash
set -euo pipefail

backup_directory=/var/backups/leave-desk
minimum_free_bytes=$((2 * 1024 * 1024 * 1024))
maximum_age_seconds=$((25 * 60 * 60))

systemctl is-active --quiet leave-desk-backup.timer || {
  echo 'Backup timer is not active' >&2
  exit 1
}
systemctl is-enabled --quiet leave-desk-backup.timer || {
  echo 'Backup timer is not enabled' >&2
  exit 1
}
[[ "$(systemctl show leave-desk-backup.service -p Result --value)" == success ]] || {
  echo 'Last backup service run failed' >&2
  exit 1
}

available_bytes=$(df -B1 --output=avail "$backup_directory" | tail -n 1)
if (( available_bytes < minimum_free_bytes )); then
  echo 'Less than 2 GiB free on the backup filesystem' >&2
  exit 1
fi

latest=
for candidate in "$backup_directory"/leave-desk-*; do
  [[ -d "$candidate" ]] || continue
  [[ "${candidate##*/}" =~ ^leave-desk-[0-9]{8}T[0-9]{6}Z$ ]] || continue
  if [[ -z "$latest" || "$candidate" > "$latest" ]]; then
    latest="$candidate"
  fi
done
[[ -n "$latest" ]] || { echo 'No completed database backup found' >&2; exit 1; }

age=$(( $(date +%s) - $(stat -c %Y "$latest") ))
if (( age < 0 || age > maximum_age_seconds )); then
  echo 'Latest database backup is older than 25 hours' >&2
  exit 1
fi

(cd "$latest" && sha256sum --status --check database.dump.sha256) || {
  echo 'Latest database backup failed checksum validation' >&2
  exit 1
}

echo 'Backup timer, service, freshness, checksum, and free space: OK'
