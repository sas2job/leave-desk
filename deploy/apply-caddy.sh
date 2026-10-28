#!/bin/sh
set -eu

release_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
deployment_root=${LEAVE_DESK_DEPLOYMENT_ROOT:-$(dirname -- "$(dirname -- "$release_directory")")}
candidate="$release_directory/Caddyfile"
configuration_directory="$deployment_root/caddy"
active="$configuration_directory/Caddyfile"
legacy_active="$deployment_root/Caddyfile"
ready_timeout=${LEAVE_DESK_CADDY_READY_TIMEOUT_SECONDS:-20}

case "$ready_timeout" in
  ''|*[!0-9]*) echo "Caddy readiness timeout must be 1–60 seconds" >&2; exit 1 ;;
esac
if [ "$ready_timeout" -lt 1 ] || [ "$ready_timeout" -gt 60 ]; then
  echo "Caddy readiness timeout must be 1–60 seconds" >&2
  exit 1
fi

reload_caddy() {
  deadline=$(( $(date +%s) + ready_timeout ))
  until "$release_directory/compose.sh" exec -T caddy curl --silent --fail \
    --max-time 2 --output /dev/null http://127.0.0.1:2019/config/ >/dev/null 2>&1; do
    if [ "$(date +%s)" -ge "$deadline" ]; then
      echo "Caddy admin endpoint unavailable after ${ready_timeout}s" >&2
      return 1
    fi
    sleep 1
  done

  if ! "$release_directory/compose.sh" exec -T caddy caddy reload \
    --config /etc/caddy/Caddyfile --adapter caddyfile; then
    echo "Caddy reload failed after admin endpoint became ready" >&2
    return 1
  fi
}

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
      if ! "$release_directory/compose.sh" up -d --force-recreate --no-deps caddy || ! reload_caddy; then
        echo "Caddy rollback restored the file but could not confirm the running configuration" >&2
      fi
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
reload_caddy
rollback_needed=0
