#!/usr/bin/env bash
# =============================================================================
# load_env_config.sh <environment>
# Reads config/<environment>.env and exports every KEY=VALUE into the GitHub
# job environment so later steps can use them ($BUNDLE_TARGET, $JOB_NAME ...).
# Windows line endings (CRLF) are tolerated.
# =============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

ENVIRONMENT="${1:?usage: load_env_config.sh <environment>}"
[[ "$ENVIRONMENT" =~ ^[a-z0-9_-]+$ ]] || die "Invalid environment name: $ENVIRONMENT"

CONFIG_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/config/${ENVIRONMENT}.env"
[[ -f "$CONFIG_FILE" ]] || die "Config file not found: config/${ENVIRONMENT}.env"

log "Loading pipeline settings from config/${ENVIRONMENT}.env"
while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line%$'\r'}"
  [[ -z "${line//[[:space:]]/}" || "$line" =~ ^[[:space:]]*# ]] && continue
  if [[ "$line" =~ ^([A-Z_][A-Z0-9_]*)=(.*)$ ]]; then
    key="${BASH_REMATCH[1]}"; value="${BASH_REMATCH[2]}"
    log "  $key=$value"
    to_env "$key" "$value"
    export "$key=$value"
  else
    die "Invalid line in config/${ENVIRONMENT}.env: $line"
  fi
done < "$CONFIG_FILE"

for required in BUNDLE_TARGET JOB_RESOURCE_KEY JOB_NAME; do
  [[ -n "${!required:-}" ]] || die "config/${ENVIRONMENT}.env is missing $required"
done
log "Configuration loaded for environment '${ENVIRONMENT}' (bundle target '${BUNDLE_TARGET}')"
