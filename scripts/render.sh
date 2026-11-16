#!/usr/bin/env bash
# Renders the chart for one cluster without touching the cluster.
# Output: rendered/<cluster>.yaml and rendered/<cluster>.images.txt
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

helm_repo
build_values_args

out="$REPO_ROOT/rendered"
mkdir -p "$out"

log "rendering $WIZ_CHART $WIZ_CHART_VERSION for cluster '$CLUSTER'"
helm template "$HELM_RELEASE" "wiz-sec/$WIZ_CHART" \
  --version "$WIZ_CHART_VERSION" \
  --namespace "$WIZ_NAMESPACE" \
  --api-versions security.openshift.io/v1 \
  "${VALUES_ARGS[@]}" > "$out/$CLUSTER.yaml"

grep -E '^[[:space:]]*-?[[:space:]]*image:' "$out/$CLUSTER.yaml" \
  | awk '{print $NF}' | tr -d "\"'" | sort -u > "$out/$CLUSTER.images.txt"

log "images referenced by the rendered manifests:"
cat "$out/$CLUSTER.images.txt" >&2

# Guard 1: every image must come from the internal mirror.
if grep -E 'azurecr\.io|registry\.wiz\.io' "$out/$CLUSTER.images.txt" >/dev/null; then
  die "rendered manifests still pull from a Wiz registry. Check the image.registry values."
fi

# Guard 2: the Wiz service account must never be rendered from values.
if grep -E '^[[:space:]]*clientToken:' "$out/$CLUSTER.yaml" >/dev/null; then
  die "a Wiz clientToken was rendered into the manifests. Credentials must not be in values files."
fi

log "render OK: rendered/$CLUSTER.yaml"
