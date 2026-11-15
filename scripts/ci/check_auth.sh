#!/usr/bin/env bash
# =============================================================================
# check_auth.sh
# Confirms the runner has the tools it needs and can authenticate to the
# Databricks workspace with the credentials from the GitHub environment.
# Supported auth (set ONE of these in the GitHub environment secrets):
#   - DATABRICKS_TOKEN                               (personal access token)
#   - DATABRICKS_CLIENT_ID + DATABRICKS_CLIENT_SECRET (service principal OAuth)
# =============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

for tool in databricks jq git; do
  command -v "$tool" >/dev/null 2>&1 || die "'$tool' is not installed on this runner (see docs/04_SELF_HOSTED_RUNNER_SETUP.md)"
done
log "Databricks CLI: $(databricks --version)"

[[ -n "${DATABRICKS_HOST:-}" ]] || die "DATABRICKS_HOST is empty - add it as a secret (or variable) on the GitHub environment"

methods=0
[[ -n "${DATABRICKS_TOKEN:-}" ]] && methods=$((methods + 1)) && log "Auth method: personal access token"
[[ -n "${DATABRICKS_CLIENT_ID:-}" && -n "${DATABRICKS_CLIENT_SECRET:-}" ]] && methods=$((methods + 1)) && log "Auth method: service principal OAuth (M2M)"
[[ $methods -eq 0 ]] && die "No Databricks credentials found. Set DATABRICKS_TOKEN, or DATABRICKS_CLIENT_ID + DATABRICKS_CLIENT_SECRET, on the GitHub environment."
[[ $methods -gt 1 ]] && die "Both a token and service principal credentials are set - keep only one method per environment."

log "Workspace: ${DATABRICKS_HOST}"
identity="$(databricks current-user me --output json | jq -r '.userName // .displayName // empty')" \
  || die "Authentication to ${DATABRICKS_HOST} failed - check the secrets on the GitHub environment"
log "Authenticated as: ${identity}"
to_env DEPLOY_IDENTITY "$identity"
