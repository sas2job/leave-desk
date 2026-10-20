#!/bin/sh
set -eu

if [ "$#" -ne 0 ]; then
  echo "Usage: apply-migrations.sh" >&2
  exit 64
fi

read_generation() {
  generation_file=$1
  generation_label=$2

  if [ ! -f "$generation_file" ] || [ -L "$generation_file" ]; then
    echo "Missing or unsafe $generation_label: $generation_file" >&2
    return 1
  fi

  generation_value=$(cat "$generation_file")
  case "$generation_value" in
    "" | *[!0-9]*)
      echo "Invalid $generation_label: $generation_file" >&2
      return 1
      ;;
  esac
  if [ "${#generation_value}" -ne 14 ]; then
    echo "Invalid $generation_label: $generation_file" >&2
    return 1
  fi

  printf '%s\n' "$generation_value"
}

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
deployment_root=${LEAVE_DESK_DEPLOYMENT_ROOT:-$(dirname -- "$(dirname -- "$script_directory")")}
rollback_floor_file="$deployment_root/schema-rollback-floor"
release_generation=$(read_generation "$script_directory/schema-compatibility" \
  "release schema compatibility")

rollback_floor=00000000000000
if [ -e "$rollback_floor_file" ] || [ -L "$rollback_floor_file" ]; then
  rollback_floor=$(read_generation "$rollback_floor_file" "schema rollback floor")
fi

if [ "$release_generation" -lt "$rollback_floor" ]; then
  echo "Release schema compatibility $release_generation is below rollback floor $rollback_floor" >&2
  exit 1
fi

"$script_directory/compose.sh" stop web
if ! "$script_directory/compose.sh" run --rm migrate; then
  echo "Database migration failed; web remains stopped" >&2
  exit 1
fi

if [ "$release_generation" -gt "$rollback_floor" ]; then
  umask 077
  rollback_floor_temporary=$(mktemp "$deployment_root/.schema-rollback-floor.XXXXXX")

  cleanup() {
    status=$?
    trap - EXIT HUP INT TERM
    if [ -n "$rollback_floor_temporary" ]; then
      rm -f -- "$rollback_floor_temporary"
    fi
    exit "$status"
  }
  trap cleanup EXIT
  trap 'exit 1' HUP INT TERM

  printf '%s\n' "$release_generation" > "$rollback_floor_temporary"
  chmod 0600 "$rollback_floor_temporary"
  sync -d "$rollback_floor_temporary"
  mv "$rollback_floor_temporary" "$rollback_floor_file"
  rollback_floor_temporary=
  sync "$deployment_root"
fi

echo "Schema rollback floor: $release_generation"
