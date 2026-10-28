#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
  echo "Usage: wait-for-health.sh URL HOST" >&2
  exit 64
fi

url=$1
host=$2
attempts=${HEALTH_ATTEMPTS:-30}
connect_timeout=${HEALTH_CONNECT_TIMEOUT:-2}
request_timeout=${HEALTH_REQUEST_TIMEOUT:-5}
retry_delay=${HEALTH_RETRY_DELAY:-2}

for value in "$attempts" "$connect_timeout" "$request_timeout" "$retry_delay"; do
  case "$value" in
    *[!0-9]* | "")
      echo "Health-check limits must be non-negative integers" >&2
      exit 64
      ;;
  esac
done
if [ "$attempts" -eq 0 ] || [ "$connect_timeout" -eq 0 ] || [ "$request_timeout" -eq 0 ]; then
  echo "Attempts and curl timeouts must be greater than zero" >&2
  exit 64
fi

attempt=1
while [ "$attempt" -le "$attempts" ]; do
  if curl --fail --silent --show-error \
    --connect-timeout "$connect_timeout" --max-time "$request_timeout" \
    --header "Host: $host" "$url"; then
    exit 0
  fi

  if [ "$attempt" -lt "$attempts" ] && [ "$retry_delay" -gt 0 ]; then
    sleep "$retry_delay"
  fi
  attempt=$((attempt + 1))
done

echo "Internal health check failed after $attempts attempts" >&2
exit 1
