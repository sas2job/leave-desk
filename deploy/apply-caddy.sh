#!/bin/sh
set -eu

cd "$(dirname "$0")"
test -f Caddyfile.next

placeholder=0
if [ ! -f Caddyfile ]; then
  : > Caddyfile
  placeholder=1
fi

# Compose supplies the same image and environment that the running service uses.
if ! docker compose run --rm --no-deps \
  -v "$PWD/Caddyfile.next:/tmp/Caddyfile:ro" \
  caddy caddy validate --config /tmp/Caddyfile --adapter caddyfile; then
  if [ "$placeholder" -eq 1 ]; then
    rm Caddyfile
  fi
  exit 1
fi

backup=$(mktemp "$PWD/Caddyfile.previous.XXXXXX")
if [ "$placeholder" -eq 0 ]; then
  cp Caddyfile "$backup"
fi
rollback_needed=1

finish() {
  status=$?
  trap - EXIT
  if [ "$rollback_needed" -eq 1 ]; then
    if [ "$placeholder" -eq 1 ]; then
      rm -f Caddyfile
    else
      cp "$backup" Caddyfile
      docker compose up -d --no-deps caddy || true
      docker compose exec -T caddy caddy reload \
        --config /etc/caddy/Caddyfile --adapter caddyfile || true
    fi
  fi
  rm -f "$backup"
  exit "$status"
}
trap finish EXIT

# Copy into the existing inode: Caddy's bind mount must see the new content.
cp Caddyfile.next Caddyfile
docker compose up -d --no-deps caddy
docker compose exec -T caddy caddy reload \
  --config /etc/caddy/Caddyfile --adapter caddyfile
rollback_needed=0
