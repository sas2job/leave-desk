#!/usr/bin/env bash
set -euo pipefail
: "${DEPLOY_HOST:?}"
: "${DEPLOY_PORT:?}"
: "${DEPLOY_USER:?}"
: "${RUNNER_TEMP:?}"
: "${DEMO_BACKUP_ARCHIVE:?}"
[[ "$DEMO_BACKUP_ARCHIVE" =~ ^/var/backups/leave-desk/demo-2026-before-correction-[[:alnum:]]{8}$ ]] || exit 64
umask 077
download_directory=$(mktemp -d "$RUNNER_TEMP/leave-desk-demo-restore.XXXXXXXX")
container="leave-desk-demo-restore-${GITHUB_RUN_ID:-local}"
container_started=0
cleanup() {
  if [ "$container_started" -eq 1 ]; then docker stop "$container" >/dev/null 2>&1 || true; fi
  rm -f -- "$download_directory/database.dump" "$download_directory/database.dump.sha256" "$download_directory/restore.stderr"
  rmdir -- "$download_directory"
}
trap cleanup EXIT
ssh -o BatchMode=yes -o StrictHostKeyChecking=yes -p "$DEPLOY_PORT" "$DEPLOY_USER@$DEPLOY_HOST" \
  "cat '$DEMO_BACKUP_ARCHIVE/database.dump'" > "$download_directory/database.dump"
ssh -o BatchMode=yes -o StrictHostKeyChecking=yes -p "$DEPLOY_PORT" "$DEPLOY_USER@$DEPLOY_HOST" \
  "cat '$DEMO_BACKUP_ARCHIVE/database.dump.sha256'" > "$download_directory/database.dump.sha256"
(cd "$download_directory" && sha256sum --status --check database.dump.sha256)
docker run -d --rm --network none --memory 512m --name "$container" \
  -e POSTGRES_HOST_AUTH_METHOD=trust -e POSTGRES_DB=restore_check postgres:16-alpine >/dev/null
container_started=1
ready=0
for _ in $(seq 1 30); do
  if [ "$(docker exec "$container" psql -X -U postgres -d restore_check -Atqc 'SELECT 1' 2>/dev/null)" = 1 ]; then ready=1; break; fi
  sleep 1
done
test "$ready" -eq 1
if ! docker exec -i "$container" pg_restore -U postgres -d restore_check \
  --no-owner --no-privileges --single-transaction --exit-on-error \
  < "$download_directory/database.dump" > /dev/null 2> "$download_directory/restore.stderr"; then
  printf 'Isolated backup restore failed; stderr_bytes=%s\n' "$(wc -c < "$download_directory/restore.stderr")" >&2
  exit 1
fi
counts=$(docker exec "$container" psql -X -U postgres -d restore_check -Atqc \
  'SELECT (SELECT COUNT(*) FROM users), (SELECT COUNT(*) FROM leave_requests), (SELECT COUNT(*) FROM leave_request_events)')
[[ "$counts" =~ ^[0-9]+\|[0-9]+\|[0-9]+$ ]] || exit 1
printf 'Backup SHA-256 and isolated restore verified; users|requests|events=%s\n' "$counts"
