#!/usr/bin/env bash
# Logs in to the target cluster with a deployer ServiceAccount token.
# Env (GitLab environment-scoped variables):
#   OPENSHIFT_API_URL    https://api.<cluster-domain>:6443
#   OPENSHIFT_TOKEN      token of the deployer ServiceAccount (masked, protected)
#   OPENSHIFT_CA_FILE    optional, File-type variable holding the API server CA bundle
set -euo pipefail
# shellcheck source=scripts/lib.sh
WIZ_CHART_VERSION="${WIZ_CHART_VERSION:-unset}" source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

need oc
: "${OPENSHIFT_API_URL:?OPENSHIFT_API_URL must be set for this environment}"
: "${OPENSHIFT_TOKEN:?OPENSHIFT_TOKEN must be set for this environment}"

args=(--server "$OPENSHIFT_API_URL" --token "$OPENSHIFT_TOKEN")
if [[ -n "${OPENSHIFT_CA_FILE:-}" ]]; then
  args+=(--certificate-authority "$OPENSHIFT_CA_FILE")
fi

oc login "${args[@]}" >/dev/null
log "logged in to $(oc whoami --show-server) as $(oc whoami)"
