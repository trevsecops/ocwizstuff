#!/usr/bin/env bash
# Post-deploy checks. Read-only. Exits non-zero when a check fails.
set -euo pipefail
# shellcheck source=scripts/lib.sh
WIZ_CHART_VERSION="${WIZ_CHART_VERSION:-unset}" source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

need oc
ns="$WIZ_NAMESPACE"
sel="app.kubernetes.io/name=wiz-sensor"
fail=0

log "pods in $ns"
oc -n "$ns" get pods -o wide

log "images in use"
oc -n "$ns" get pods -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.image}{"\n"}{end}{end}' | sort -u

if [[ "$SECRETS_MODE" == "external" ]]; then
  es_ready="$(oc -n "$ns" get externalsecret wiz-api-token \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
  if [[ "$es_ready" == "True" ]]; then
    log "ExternalSecret wiz-api-token is Ready (synced from CyberArk)"
  else
    log "FAIL: ExternalSecret wiz-api-token is not Ready"; fail=1
  fi
fi

ds="$(oc -n "$ns" get ds -l "$sel" -o name | head -1)"
if [[ -z "$ds" ]]; then
  log "FAIL: no Sensor DaemonSet found"; fail=1
else
  oc -n "$ns" get "$ds"
  oc -n "$ns" rollout status "$ds" --timeout=5m || { log "FAIL: Sensor DaemonSet is not fully rolled out"; fail=1; }
fi

pod="$(oc -n "$ns" get pod -l "$sel" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
if [[ -n "$pod" ]]; then
  scc="$(oc -n "$ns" get pod "$pod" -o jsonpath='{.metadata.annotations.openshift\.io/scc}')"
  log "Sensor pod $pod admitted under SCC: ${scc:-unknown}"
  [[ "$scc" == *-scc ]] || { log "FAIL: Sensor is not running under the chart SCC"; fail=1; }

  # Proof that the Sensor authenticated and pulled content from the tenant.
  ok=0
  for _ in $(seq 1 12); do
    if oc -n "$ns" logs "$pod" -c wiz-sensor --tail=-1 2>/dev/null | grep -q 'ending content update'; then ok=1; break; fi
    sleep 15
  done
  if [[ $ok -eq 1 ]]; then
    log "Sensor reached Wiz (content update completed)"
  else
    log "FAIL: no 'ending content update' in Sensor logs after 3 minutes. Check egress and proxy."; fail=1
  fi
else
  log "FAIL: no Sensor pod found"; fail=1
fi

log "Connector and Broker workloads"
oc -n "$ns" get deploy,job 2>/dev/null || true
oc -n "$ns" wait --for=condition=Available deploy --all --timeout=3m \
  || { log "FAIL: a Connector/Broker deployment is not Available"; fail=1; }

[[ $fail -eq 0 ]] || die "validation failed"
log "validation passed. Confirm in the Wiz portal: Settings > Deployments (Connector connected, Sensors Active within about 10 minutes)."
