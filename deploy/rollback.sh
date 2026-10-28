#!/bin/sh
set -eu

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "Usage: rollback.sh RELEASE_ID [GHCR_USERNAME]" >&2
  exit 64
fi

release_id=$1
ghcr_username=${2-}
case "$release_id" in
  *[!a-zA-Z0-9._-]* | "")
    echo "Invalid release identifier" >&2
    exit 64
    ;;
esac
if [ -n "$ghcr_username" ]; then
  case "$ghcr_username" in
    *[!a-zA-Z0-9_-]*)
      echo "Invalid GHCR username" >&2
      exit 64
      ;;
  esac
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
target_release="$deployment_root/releases/$release_id"
if [ ! -d "$target_release" ] || [ -L "$target_release" ]; then
  echo "Release not found: $release_id" >&2
  exit 1
fi

rollback_floor=00000000000000
rollback_floor_file="$deployment_root/schema-rollback-floor"
if [ -e "$rollback_floor_file" ] || [ -L "$rollback_floor_file" ]; then
  rollback_floor=$(read_generation "$rollback_floor_file" "schema rollback floor")
fi

target_generation=00000000000000
target_generation_file="$target_release/schema-compatibility"
if [ -e "$target_generation_file" ] || [ -L "$target_generation_file" ]; then
  target_generation=$(read_generation "$target_generation_file" \
    "release schema compatibility")
fi

if [ "$target_generation" -lt "$rollback_floor" ]; then
  echo "Release schema compatibility $target_generation is below rollback floor $rollback_floor" >&2
  exit 1
fi

image=$(sed -n 's/^LEAVE_DESK_IMAGE=//p' "$target_release/release.env")
case "$image" in
  ghcr.io/?*@sha256:*)
    image_repository=${image%@sha256:*}
    image_digest=${image##*@sha256:}
    if [ "${#image_digest}" -ne 64 ]; then
      echo "Release has an invalid image digest" >&2
      exit 1
    fi
    case "$image_repository" in
      *[!a-zA-Z0-9._/-]* | *[@:]* )
        echo "Release has an invalid image repository" >&2
        exit 1
        ;;
    esac
    case "$image_digest" in
      *[!0-9a-f]*)
        echo "Release has an invalid image digest" >&2
        exit 1
        ;;
    esac
    ;;
  ghcr.io/*:*)
    # Releases published before digest pinning retain their legacy SHA tag.
    ;;
  *)
    echo "Release has an invalid image reference" >&2
    exit 1
    ;;
esac
case "$image" in
  *[!a-zA-Z0-9._/:@-]*)
    echo "Release has an invalid image reference" >&2
    exit 1
    ;;
esac

docker_config=
next_link=

discard_credentials() {
  if [ -n "$docker_config" ]; then
    docker --config "$docker_config" logout ghcr.io >/dev/null 2>&1 || true
    rm -f -- "$docker_config/config.json"
    rmdir -- "$docker_config"
    docker_config=
  fi
}

cleanup() {
  status=$?
  trap - EXIT HUP INT TERM
  discard_credentials || true
  if [ -n "$next_link" ]; then
    rm -f -- "$next_link"
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

if docker image inspect "$image" >/dev/null 2>&1; then
  echo "Using cached rollback image: $image"
else
  if [ -z "$ghcr_username" ]; then
    echo "Rollback image is not cached; provide a GHCR username and token on stdin" >&2
    exit 1
  fi

  runtime_directory=${ROLLBACK_RUNTIME_DIRECTORY:-${XDG_RUNTIME_DIR:-/tmp}}
  docker_config=$(mktemp -d "$runtime_directory/leave-desk-rollback-docker.XXXXXX")
  chmod 0700 "$docker_config"
  docker --config "$docker_config" login ghcr.io \
    --username "$ghcr_username" --password-stdin
  docker --config "$docker_config" pull "$image"
  discard_credentials

  if ! docker image inspect "$image" >/dev/null 2>&1; then
    echo "Rollback image is unavailable after pull: $image" >&2
    exit 1
  fi
fi

"$target_release/compose.sh" config --quiet

next_link="$deployment_root/.current.rollback.$$"
ln -s "releases/$release_id" "$next_link"
mv -T "$next_link" "$deployment_root/current"
next_link=
sync "$deployment_root"

"$target_release/compose.sh" up -d --no-deps --pull never web
