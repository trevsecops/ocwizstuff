#!/usr/bin/env bash
# Shared settings and helpers. Sourced by the other scripts.
# shellcheck shell=bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_ROOT

: "${WIZ_NAMESPACE:=wiz}"
: "${HELM_RELEASE:=wiz-integration}"
: "${WIZ_HELM_REPO_URL:=https://charts.wiz.io/}"
: "${WIZ_CHART:=wiz-kubernetes-integration}"
: "${WIZ_CHART_VERSION:?WIZ_CHART_VERSION must be set (pinned in .gitlab-ci.yml)}"
: "${HELM_TIMEOUT:=15m}"
: "${EXTRA_VALUES:=}"
# How the wiz-api-token Secret gets into the cluster:
#   external  External Secrets Operator syncs it from CyberArk (default)
#   ci        scripts/create-secrets.sh writes it from masked CI variables (fallback only)
: "${SECRETS_MODE:=external}"

log()  { printf '[%s] %s\n' "$(date -u +%H:%M:%SZ)" "$*" >&2; }
die()  { log "ERROR: $*"; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "required tool not found: $1"; }

require_cluster() {
  : "${CLUSTER:?CLUSTER must be set to a file name in helm/values/clusters (without .yaml)}"
  [[ "$CLUSTER" != _* ]] || die "CLUSTER must not be the template"
  [[ -f "$REPO_ROOT/helm/values/clusters/$CLUSTER.yaml" ]] \
    || die "no values file for cluster '$CLUSTER'"
}

# Prints the values files for the current cluster, one per line, in merge order:
# base, cluster, then optional overlays named in EXTRA_VALUES (space separated,
# file names from helm/values/optional without .yaml, for example "proxy pull-secret").
values_files() {
  require_cluster
  echo "$REPO_ROOT/helm/values/base.yaml"
  echo "$REPO_ROOT/helm/values/clusters/$CLUSTER.yaml"
  local extra
  for extra in $EXTRA_VALUES; do
    [[ -f "$REPO_ROOT/helm/values/optional/$extra.yaml" ]] \
      || die "EXTRA_VALUES names '$extra' but helm/values/optional/$extra.yaml does not exist"
    echo "$REPO_ROOT/helm/values/optional/$extra.yaml"
  done
}

# Fills the global array VALUES_ARGS with "--values <file>" pairs.
# The list is resolved in the current shell so that a bad CLUSTER or overlay name aborts the script.
build_values_args() {
  local list f
  list="$(values_files)" || exit 1
  VALUES_ARGS=()
  while IFS= read -r f; do
    VALUES_ARGS+=(--values "$f")
  done <<< "$list"
}

# Prints the ExternalSecret manifest for the current cluster: a per-cluster copy if one exists,
# otherwise the shared default.
external_secret_file() {
  require_cluster
  local dir="$REPO_ROOT/manifests/external-secrets"
  if [[ -f "$dir/clusters/$CLUSTER.yaml" ]]; then
    echo "$dir/clusters/$CLUSTER.yaml"
  else
    echo "$dir/wiz-api-token.yaml"
  fi
}

extra_enabled() {
  local extra
  for extra in $EXTRA_VALUES; do
    [[ "$extra" == "$1" ]] && return 0
  done
  return 1
}

helm_repo() {
  need helm
  helm repo add wiz-sec "$WIZ_HELM_REPO_URL" --force-update >/dev/null
  helm repo update wiz-sec >/dev/null
}
