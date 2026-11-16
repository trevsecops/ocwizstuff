#!/usr/bin/env bash
# FALLBACK path (SECRETS_MODE=ci) and the optional registry pull secret.
# The standard path is CyberArk through the External Secrets Operator: scripts/apply-external-secrets.sh
#
# Creates or updates Secrets from environment variables only.
#
#   wiz-api-token          SECRETS_MODE=ci only. Wiz service account (type: Complete Kubernetes Integration).
#                          Env: WIZ_CLIENT_ID, WIZ_CLIENT_SECRET
#   wiz-private-registry   only when EXTRA_VALUES contains "pull-secret".
#                          Env: PRIVATE_REGISTRY, PRIVATE_REGISTRY_USERNAME, PRIVATE_REGISTRY_PASSWORD
#
# The Sensor image comes from the internal mirror, so no Wiz registry pull key is used.
# It does not remove the need for wiz-api-token: that is how the Sensor, Connector and Broker
# authenticate to the Wiz tenant.
set -euo pipefail
# shellcheck source=scripts/lib.sh
WIZ_CHART_VERSION="${WIZ_CHART_VERSION:-unset}" source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

need oc
# Values are passed through file descriptors so they never appear in the process list or job log.
if [[ "${SKIP_API_TOKEN:-0}" != "1" ]]; then
  : "${WIZ_CLIENT_ID:?WIZ_CLIENT_ID must be set}"
  : "${WIZ_CLIENT_SECRET:?WIZ_CLIENT_SECRET must be set}"
  oc -n "$WIZ_NAMESPACE" create secret generic wiz-api-token \
    --from-file=clientId=<(printf '%s' "$WIZ_CLIENT_ID") \
    --from-file=clientToken=<(printf '%s' "$WIZ_CLIENT_SECRET") \
    --dry-run=client -o yaml | oc apply -f - >/dev/null
  log "secret wiz-api-token applied in namespace $WIZ_NAMESPACE"
fi

if extra_enabled pull-secret; then
  : "${PRIVATE_REGISTRY:?PRIVATE_REGISTRY must be set}"
  : "${PRIVATE_REGISTRY_USERNAME:?PRIVATE_REGISTRY_USERNAME must be set}"
  : "${PRIVATE_REGISTRY_PASSWORD:?PRIVATE_REGISTRY_PASSWORD must be set}"
  host="${PRIVATE_REGISTRY%%/*}"
  auth="$(printf '%s:%s' "$PRIVATE_REGISTRY_USERNAME" "$PRIVATE_REGISTRY_PASSWORD" | base64 | tr -d '\n')"
  oc -n "$WIZ_NAMESPACE" create secret generic wiz-private-registry \
    --type=kubernetes.io/dockerconfigjson \
    --from-file=.dockerconfigjson=<(printf '{"auths":{"%s":{"auth":"%s"}}}' "$host" "$auth") \
    --dry-run=client -o yaml | oc apply -f - >/dev/null
  log "secret wiz-private-registry applied in namespace $WIZ_NAMESPACE"
fi
