#!/bin/sh
set -eu

if [ "$#" -ne 4 ]; then
  echo "Usage: publish-release.sh DEPLOYMENT_ROOT STAGING_DIRECTORY RELEASE_ID IMAGE" >&2
  exit 64
fi

deployment_root=$1
staging_directory=$2
release_id=$3
image=$4

case "$release_id" in
  *[!a-zA-Z0-9._-]* | "")
    echo "Invalid release identifier" >&2
    exit 64
    ;;
esac

image_repository=${image%@sha256:*}
image_digest=${image##*@sha256:}
if [ "$image_repository" = "$image" ] || [ "${#image_digest}" -ne 64 ]; then
  echo "Release image must use a sha256 digest" >&2
  exit 64
fi
case "$image_repository" in
  ghcr.io/?*) ;;
  *)
    echo "Invalid release image repository" >&2
    exit 64
    ;;
esac
case "$image_repository" in
  *[!a-zA-Z0-9._/-]* | *[@:]* )
    echo "Invalid release image repository" >&2
    exit 64
    ;;
esac
case "$image_digest" in
  *[!0-9a-f]*)
    echo "Invalid release image digest" >&2
    exit 64
    ;;
esac

deployment_root=$(CDPATH= cd -- "$deployment_root" && pwd -P)
staging_directory=$(CDPATH= cd -- "$staging_directory" && pwd -P)
incoming_root=$(CDPATH= cd -- "$deployment_root/.incoming" && pwd -P)

case "$staging_directory/" in
  "$incoming_root"/*/) ;;
  *)
    echo "Staging directory must be below $incoming_root" >&2
    exit 64
    ;;
esac

mkdir -p -- "$deployment_root/releases" "$deployment_root/caddy"
deployment_device=$(stat -c %d "$deployment_root")
staging_device=$(stat -c %d "$staging_directory")
releases_device=$(stat -c %d "$deployment_root/releases")
if [ "$staging_device" != "$deployment_device" ] || [ "$releases_device" != "$deployment_device" ]; then
  echo "Staging and release directories must use the deployment filesystem" >&2
  exit 1
fi

required_files='Caddyfile
apply-caddy.sh
backup.sh
compose.sh
compose.yml
leave-desk-backup.service
leave-desk-backup.timer
leave-desk-cache-cleanup.service
leave-desk-cache-cleanup.timer
leave-desk-session-prune.service
leave-desk-session-prune.timer
publish-release.sh
rollback.sh
wait-for-health.sh'

for file in $required_files; do
  if [ ! -f "$staging_directory/$file" ] || [ -L "$staging_directory/$file" ]; then
    echo "Missing or unsafe release file: $file" >&2
    exit 1
  fi
done

if [ ! -f "$staging_directory/SHA256SUMS" ] || [ -L "$staging_directory/SHA256SUMS" ]; then
  echo "Missing or unsafe release file: SHA256SUMS" >&2
  exit 1
fi

(cd "$staging_directory" && sha256sum --check --strict SHA256SUMS)

umask 077
release_environment=$(mktemp "$staging_directory/.release.env.XXXXXX")
next_link=

cleanup() {
  status=$?
  trap - EXIT HUP INT TERM
  if [ -n "$release_environment" ]; then
    rm -f -- "$release_environment"
  fi
  if [ -n "$next_link" ]; then
    rm -f -- "$next_link"
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

printf 'LEAVE_DESK_IMAGE=%s\n' "$image" > "$release_environment"
chmod 0600 "$release_environment"
mv "$release_environment" "$staging_directory/release.env"
release_environment=
chmod 0755 "$staging_directory/apply-caddy.sh" "$staging_directory/backup.sh" \
  "$staging_directory/compose.sh" "$staging_directory/publish-release.sh" \
  "$staging_directory/rollback.sh" "$staging_directory/wait-for-health.sh"
for file in $required_files SHA256SUMS release.env; do
  sync -d "$staging_directory/$file"
done
sync "$staging_directory"

release_directory="$deployment_root/releases/$release_id"
if [ -e "$release_directory" ] || [ -L "$release_directory" ]; then
  echo "Release already exists: $release_id" >&2
  exit 1
fi

# Both directories are below deployment_root, so this publishes a complete
# release with one rename on the destination filesystem.
mv "$staging_directory" "$release_directory"
sync "$deployment_root/releases"

next_link="$deployment_root/.current.$release_id.$$"
ln -s "releases/$release_id" "$next_link"
mv -T "$next_link" "$deployment_root/current"
next_link=
sync "$deployment_root"
