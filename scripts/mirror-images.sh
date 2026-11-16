#!/usr/bin/env bash
# Copies the images in images/images.txt into the internal registry, preserving the path.
# Only public Wiz images are listed there (the Broker). The Sensor image is mirrored by an
# existing internal process and is out of scope for this script.
# Run from a runner that can reach wiziopublic.azurecr.io and the internal registry.
#
# Required env:  PRIVATE_REGISTRY               host[:port][/prefix] of the internal registry
# Optional env:  PRIVATE_REGISTRY_USERNAME / PRIVATE_REGISTRY_PASSWORD   push credentials
#                DRY_RUN=1                                               print the copies only
set -euo pipefail
# shellcheck source=scripts/lib.sh
WIZ_CHART_VERSION="${WIZ_CHART_VERSION:-unset}" source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

need skopeo
: "${PRIVATE_REGISTRY:?PRIVATE_REGISTRY must be set}"
[[ "$PRIVATE_REGISTRY" != *"<"* ]] || die "PRIVATE_REGISTRY still holds a placeholder"
dest_root="${PRIVATE_REGISTRY%/}"
dest_host="${dest_root%%/*}"

if [[ -n "${PRIVATE_REGISTRY_USERNAME:-}" ]]; then
  printf '%s' "${PRIVATE_REGISTRY_PASSWORD:?}" \
    | skopeo login "$dest_host" --username "$PRIVATE_REGISTRY_USERNAME" --password-stdin
fi

count=0
while IFS= read -r line; do
  src="${line%%#*}"
  src="${src//[[:space:]]/}"
  [[ -n "$src" ]] || continue
  [[ "$src" != wizio.azurecr.io/* ]] \
    || die "$src is in the private Wiz registry. Those images come from the existing internal mirror, not this job."
  path="${src#*/}"                       # drop the source registry host
  dst="$dest_root/$path"
  log "copy $src -> $dst"
  if [[ "${DRY_RUN:-0}" != "1" ]]; then
    # --all keeps every architecture of a multi-arch image.
    skopeo copy --all --retry-times 3 "docker://$src" "docker://$dst"
    skopeo inspect --format '{{.Digest}}' "docker://$dst" | sed "s|^|  digest: |" >&2
  fi
  count=$((count + 1))
done < "$REPO_ROOT/images/images.txt"

[[ $count -gt 0 ]] || die "images/images.txt lists no images"
log "mirrored $count image(s)"
