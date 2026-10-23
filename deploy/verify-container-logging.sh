#!/bin/sh
set -eu

release_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)

for service in caddy db web; do
  container_id=$("$release_directory/compose.sh" ps -q "$service")
  if [ -z "$container_id" ]; then
    echo "No running container for $service" >&2
    exit 1
  fi

  actual=$(docker inspect --format \
    '{{.HostConfig.LogConfig.Type}} {{index .HostConfig.LogConfig.Config "max-size"}} {{index .HostConfig.LogConfig.Config "max-file"}}' \
    "$container_id")
  if [ "$actual" != 'json-file 10m 3' ]; then
    echo "Unexpected Docker logging configuration for $service" >&2
    exit 1
  fi
done

echo "Docker logging configuration verified for caddy, db and web"
