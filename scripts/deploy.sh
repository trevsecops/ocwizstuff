#!/usr/bin/env bash
# Installs or upgrades the Wiz release on the cluster the current oc/kube context points at.
# Order: placeholder gate -> namespace -> wiz-api-token (CyberArk via ExternalSecret) -> helm upgrade --install.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

need oc
"$REPO_ROOT/scripts/check-placeholders.sh" --strict

log "target cluster: $(oc whoami --show-server)  release: $HELM_RELEASE  namespace: $WIZ_NAMESPACE"

oc apply -f "$REPO_ROOT/manifests/namespace.yaml"
case "$SECRETS_MODE" in
  external)
    "$REPO_ROOT/scripts/apply-external-secrets.sh"
    # The registry pull secret, when that overlay is on, still comes from CI variables.
    if extra_enabled pull-secret; then SKIP_API_TOKEN=1 "$REPO_ROOT/scripts/create-secrets.sh"; fi
    ;;
  ci)
    log "WARNING: SECRETS_MODE=ci. The Wiz credential is read from CI variables, not CyberArk."
    "$REPO_ROOT/scripts/create-secrets.sh"
    ;;
  *) die "SECRETS_MODE must be 'external' or 'ci' (got '$SECRETS_MODE')" ;;
esac

helm_repo
build_values_args

helm upgrade --install "$HELM_RELEASE" "wiz-sec/$WIZ_CHART" \
  --version "$WIZ_CHART_VERSION" \
  --namespace "$WIZ_NAMESPACE" \
  "${VALUES_ARGS[@]}" \
  --wait --timeout "$HELM_TIMEOUT"

helm status "$HELM_RELEASE" --namespace "$WIZ_NAMESPACE"
