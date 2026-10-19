#!/bin/sh
set -eu

release_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
deployment_root=${LEAVE_DESK_DEPLOYMENT_ROOT:-$(dirname -- "$(dirname -- "$release_directory")")}
candidate="$release_directory/Caddyfile"
configuration_directory="$deployment_root/caddy"
active="$configuration_directory/Caddyfile"
legacy_active="$deployment_root/Caddyfile"

test -f "$candidate"
mkdir -p -- "$configuration_directory"

# Compose supplies the same image and environment that the running service uses.
"$release_directory/compose.sh" run --rm --no-deps \
  -v "$candidate:/tmp/Caddyfile:ro" \
  caddy caddy validate --config /tmp/Caddyfile --adapter caddyfile

umask 077
candidate_copy=$(mktemp "$configuration_directory/.Caddyfile.next.XXXXXX")
backup=
rollback_needed=0

cleanup() {
  status=$?
  trap - EXIT HUP INT TERM

  if [ "$rollback_needed" -eq 1 ] && [ -n "$backup" ]; then
    restore=$(mktemp "$configuration_directory/.Caddyfile.restore.XXXXXX")
    if cp -- "$backup" "$restore" && sync -d "$restore" && mv -f -- "$restore" "$active"; then
      sync "$configuration_directory"
      "$release_directory/compose.sh" up -d --no-deps caddy || true
      "$release_directory/compose.sh" exec -T caddy caddy reload \
        --config /etc/caddy/Caddyfile --adapter caddyfile || true
    else
      rm -f -- "$restore"
    fi
  fi

  if [ -n "$candidate_copy" ]; then
    rm -f -- "$candidate_copy"
  fi
  if [ -n "$backup" ]; then
    rm -f -- "$backup"
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

if [ ! -f "$active" ] && [ -f "$legacy_active" ]; then
  migrated=$(mktemp "$configuration_directory/.Caddyfile.migrate.XXXXXX")
  cp -- "$legacy_active" "$migrated"
  chmod 0644 "$migrated"
  sync -d "$migrated"
  mv -f -- "$migrated" "$active"
  sync "$configuration_directory"
fi

if [ -f "$active" ]; then
  backup=$(mktemp "$configuration_directory/.Caddyfile.previous.XXXXXX")
  cp -- "$active" "$backup"
  rollback_needed=1
fi

cp -- "$candidate" "$candidate_copy"
chmod 0644 "$candidate_copy"
sync -d "$candidate_copy"
mv -f -- "$candidate_copy" "$active"
candidate_copy=
sync "$configuration_directory"

# A directory bind mount observes the atomically replaced file. The first run
# also recreates a legacy container that still has the former single-file mount.
"$release_directory/compose.sh" up -d --no-deps caddy
"$release_directory/compose.sh" exec -T caddy caddy reload \
  --config /etc/caddy/Caddyfile --adapter caddyfile
rollback_needed=0
