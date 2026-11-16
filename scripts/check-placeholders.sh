#!/usr/bin/env bash
# Finds unresolved <PLACEHOLDER> tokens.
#   check-placeholders.sh            report every placeholder in the repo, always exits 0
#   check-placeholders.sh --strict   check only what the current CLUSTER deploys, exit 1 if any remain
set -euo pipefail
# shellcheck source=scripts/lib.sh
WIZ_CHART_VERSION="${WIZ_CHART_VERSION:-unset}" source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

PATTERN='<[A-Z][A-Z0-9_]+>'

if [[ "${1:-}" == "--strict" ]]; then
  list="$(values_files)" || exit 1
  mapfile -t files <<< "$list"
  files+=("$REPO_ROOT/manifests/namespace.yaml")
  if [[ "$SECRETS_MODE" == "external" ]]; then
    es="$(external_secret_file)" || exit 1
    files+=("$es")
  fi
  found=0
  for f in "${files[@]}"; do
    # Comments are ignored in strict mode. Only live YAML blocks the deploy.
    if hits=$(sed -E 's/(^|[[:space:]])#.*$//' "$f" | grep -nE "$PATTERN"); then
      found=1
      printf '%s\n' "$hits" | sed "s|^|${f#"$REPO_ROOT"/}:|"
    fi
  done
  [[ $found -eq 0 ]] || die "unresolved placeholders for cluster '$CLUSTER' (listed above)"
  log "no unresolved placeholders for cluster '$CLUSTER'"
else
  cd "$REPO_ROOT"
  log "placeholders still present (informational):"
  grep -rnE "$PATTERN" --exclude-dir=.git --exclude-dir=rendered --exclude-dir=docs \
    --exclude=README.md --exclude=_template.yaml --exclude-dir=examples . || log "none"
fi
