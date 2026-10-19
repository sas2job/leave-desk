#!/bin/sh
set -eu

release_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
deployment_root=${LEAVE_DESK_DEPLOYMENT_ROOT:-$(dirname -- "$(dirname -- "$release_directory")")}

exec docker compose \
  --project-directory "$deployment_root" \
  --env-file "$deployment_root/.env" \
  --env-file "$release_directory/release.env" \
  -f "$release_directory/compose.yml" "$@"
