#!/usr/bin/env bash
# SECRETS_MODE=external: applies the ExternalSecret and waits until the External Secrets Operator
# has synced the Wiz service account from CyberArk into the wiz-api-token Secret.
# No Wiz credential passes through GitLab in this mode.
set -euo pipefail
# shellcheck source=scripts/lib.sh
WIZ_CHART_VERSION="${WIZ_CHART_VERSION:-unset}" source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

need oc
file="$(external_secret_file)" || exit 1

oc get crd externalsecrets.external-secrets.io >/dev/null 2>&1 \
  || die "External Secrets Operator is not installed on this cluster (CRD externalsecrets.external-secrets.io missing)"

log "applying ${file#"$REPO_ROOT"/}"
oc apply -f "$file"

if ! oc -n "$WIZ_NAMESPACE" wait externalsecret/wiz-api-token --for=condition=Ready --timeout=180s; then
  oc -n "$WIZ_NAMESPACE" get externalsecret wiz-api-token \
    -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.reason}: {.message}{"\n"}{end}' >&2 || true
  die "ExternalSecret wiz-api-token did not become Ready. Check the store name, the CyberArk paths and the operator logs."
fi

# Confirm both keys arrived. Only lengths are inspected, values are never printed.
for key in clientId clientToken; do
  len="$(oc -n "$WIZ_NAMESPACE" get secret wiz-api-token -o "jsonpath={.data.$key}" | wc -c)"
  [[ "$len" -gt 0 ]] || die "Secret wiz-api-token has no value for key '$key'"
done
log "secret wiz-api-token synced from CyberArk in namespace $WIZ_NAMESPACE"
