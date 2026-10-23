#!/usr/bin/env bash
set -euo pipefail

: "${DEPLOY_HOST:?}"
: "${DEPLOY_PORT:?}"
: "${DEPLOY_USER:?}"

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
result=$(ssh -o BatchMode=yes -o StrictHostKeyChecking=yes -p "$DEPLOY_PORT" \
  "$DEPLOY_USER@$DEPLOY_HOST" \
  'cd /root/projects/leave-desk && ./current/compose.sh exec -T db psql -X -U leave_desk -d leave_desk_production -v ON_ERROR_STOP=1 -A -t -F ,' \
  < "$script_directory/audit-cancelled-approval-history.sql")

IFS=, read -r total valid invalid same_time <<< "$result"
for count in "$total" "$valid" "$invalid" "$same_time"; do
  if [[ ! "$count" =~ ^[0-9]+$ ]]; then
    echo 'Leave history audit returned an invalid aggregate' >&2
    exit 1
  fi
done

printf 'Reviewed cancellations: %s; valid histories: %s; invalid histories: %s; approvals at review time: %s\n' \
  "$total" "$valid" "$invalid" "$same_time"
test "$invalid" -eq 0
