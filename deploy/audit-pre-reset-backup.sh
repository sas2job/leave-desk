#!/usr/bin/env bash
set -euo pipefail

: "${DEPLOY_HOST:?}"
: "${DEPLOY_PORT:?}"
: "${DEPLOY_USER:?}"
: "${RUNNER_TEMP:?}"

archive=/var/backups/leave-desk/leave-desk-20261020T020027Z
script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
download_directory=$(mktemp -d "$RUNNER_TEMP/leave-desk-pre-reset.XXXXXXXX")
chmod 0700 "$download_directory"
container="leave-desk-history-audit-${GITHUB_RUN_ID:-local}"
container_started=0

cleanup() {
  if [ "$container_started" -eq 1 ]; then
    docker stop "$container" >/dev/null 2>&1 || true
  fi
  rm -f -- "$download_directory/database.dump" \
    "$download_directory/database.dump.sha256" "$download_directory/restore.stderr"
  rmdir -- "$download_directory"
}
trap cleanup EXIT

ssh -o BatchMode=yes -o StrictHostKeyChecking=yes -p "$DEPLOY_PORT" \
  "$DEPLOY_USER@$DEPLOY_HOST" "cat '$archive/database.dump'" \
  > "$download_directory/database.dump"
ssh -o BatchMode=yes -o StrictHostKeyChecking=yes -p "$DEPLOY_PORT" \
  "$DEPLOY_USER@$DEPLOY_HOST" "cat '$archive/database.dump.sha256'" \
  > "$download_directory/database.dump.sha256"
(cd "$download_directory" && sha256sum --status --check database.dump.sha256)

docker run -d --rm --network none --memory 512m --name "$container" \
  -e POSTGRES_PASSWORD=isolated-audit -e POSTGRES_DB=audit \
  postgres:16-alpine >/dev/null
container_started=1

ready=0
for _ in $(seq 1 30); do
  if [ "$(docker exec "$container" psql -X -U postgres -d audit -Atqc 'SELECT 1' 2>/dev/null)" = 1 ]; then
    ready=1
    break
  fi
  sleep 1
done
if [ "$ready" -ne 1 ]; then
  echo 'Isolated PostgreSQL did not become ready' >&2
  exit 1
fi

if docker exec -i "$container" pg_restore -U postgres -d audit \
  --no-owner --no-privileges --single-transaction --exit-on-error \
  < "$download_directory/database.dump" > /dev/null \
  2> "$download_directory/restore.stderr"; then
  :
else
  restore_status=$?
  restore_error=$(cat "$download_directory/restore.stderr")
  case "$restore_error" in
    *'unsupported version'* | *'input file does not appear to be a valid archive'*)
      reason='incompatible archive format' ;;
    *'could not read from input file'* | *'end of file'* | *'did not find magic string'*)
      reason='archive read error' ;;
    *'unrecognized configuration parameter'*) reason='server setting incompatibility' ;;
    *'role '*'does not exist'*) reason='missing database role' ;;
    *'extension '*'is not available'*) reason='missing database extension' ;;
    *'already exists'*) reason='object already exists in isolated database' ;;
    *'permission denied'*) reason='database permission error' ;;
    *'No space left on device'*) reason='runner storage exhausted' ;;
    *'out of memory'* | *'Killed'*) reason='memory limit exceeded' ;;
    *'could not connect to server'* | *'server closed the connection'*)
      reason='isolated database connection failed' ;;
    *'COPY failed'* | *'invalid input syntax'*) reason='data restore error' ;;
    *'could not execute query'*) reason='schema restore error' ;;
    *) reason='unclassified restore error' ;;
  esac
  printf 'Historical archive restore failed: %s; exit=%s; stderr_bytes=%s' \
    "$reason" "$restore_status" "$(wc -c < "$download_directory/restore.stderr")" >&2
  if [ "$reason" = 'unclassified restore error' ]; then
    markers=''
    for marker in pg_restore docker connection archive input file read open header magic \
      unexpected invalid fatal error denied memory disk space COPY query role extension \
      schema database relation constraint table index trigger sequence type collation \
      duplicate syntax command stdin version parameter tablespace encoding terminated \
      failed warning public; do
      if [[ "${restore_error,,}" == *"${marker,,}"* ]]; then
        markers="${markers}${markers:+,}${marker}"
      fi
    done
    printf '; markers=%s' "${markers:-none}" >&2
  fi
  printf '\n' >&2
  exit 1
fi

result=$(docker exec -i "$container" psql -X -U postgres -d audit \
  -v ON_ERROR_STOP=1 -A -t -F , \
  < "$script_directory/audit-cancelled-approval-history.sql")
IFS=, read -r total valid invalid same_time <<< "$result"
for count in "$total" "$valid" "$invalid" "$same_time"; do
  [[ "$count" =~ ^[0-9]+$ ]] || {
    echo 'Historical audit returned an invalid aggregate' >&2
    exit 1
  }
done

without_notification=$(docker exec "$container" psql -X -U postgres -d audit \
  -v ON_ERROR_STOP=1 -A -t -c '
    SELECT COUNT(*)
    FROM leave_requests requests
    JOIN leave_request_events approvals
      ON approvals.leave_request_id = requests.id
    WHERE requests.status = 3
      AND requests.reviewer_id IS NOT NULL
      AND approvals.event_type = 1
      AND approvals.actor_id = requests.reviewer_id
      AND approvals.occurred_at = requests.reviewed_at
      AND NOT EXISTS (
        SELECT 1 FROM notifications
        WHERE notifications.leave_request_event_id = approvals.id
      )')
[[ "$without_notification" =~ ^[0-9]+$ ]] || {
  echo 'Historical approval count is invalid' >&2
  exit 1
}

printf 'Pre-reset archive: reviewed cancellations=%s; valid histories=%s; invalid histories=%s; approvals without notifications=%s\n' \
  "$total" "$valid" "$invalid" "$without_notification"
test "$invalid" -eq 0
