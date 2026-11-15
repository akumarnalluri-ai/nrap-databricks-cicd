#!/usr/bin/env bash
# =============================================================================
# deploy_bundle.sh <bundle-dir> <target> <version> [log-name]
# Validates and deploys the Databricks Asset Bundle found in <bundle-dir>
# (the checked-out release tag) to the given target.
#
# Optional env: FORCE_LOCK=true  -> pass --force-lock (clears a stale deploy
#               lock left by a cancelled run; use with care).
# =============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

BUNDLE_DIR="${1:?bundle dir required}"
TARGET="${2:?target required}"
VERSION="${3:?version required}"
LOG_NAME="${4:-deploy}"

[[ -f "$BUNDLE_DIR/databricks.yml" ]] || die "No databricks.yml in $BUNDLE_DIR - is the tag a valid bundle release?"
cd "$BUNDLE_DIR" || die "Cannot cd to $BUNDLE_DIR"

VAR_ARGS=(--var="release_version=${VERSION}")

log "===== Validating bundle (target=${TARGET}, version=${VERSION}) ====="
run_logged "$LOG_NAME" databricks bundle validate -t "$TARGET" "${VAR_ARGS[@]}" \
  || die "Bundle validation failed for ${VERSION} on ${TARGET}"

DEPLOY_ARGS=(-t "$TARGET" "${VAR_ARGS[@]}" --auto-approve)
is_true "${FORCE_LOCK:-false}" && DEPLOY_ARGS+=(--force-lock) && warn "FORCE_LOCK=true - overriding any existing deployment lock"

log "===== Deploying bundle (target=${TARGET}, version=${VERSION}) ====="
run_logged "$LOG_NAME" databricks bundle deploy "${DEPLOY_ARGS[@]}" \
  || die "Bundle deploy failed for ${VERSION} on ${TARGET} (see ${LOG_NAME}.log)"

log "===== Deployed resources ====="
run_logged "$LOG_NAME" databricks bundle summary -t "$TARGET" "${VAR_ARGS[@]}" || warn "bundle summary failed (non-fatal)"

log "Deploy of ${VERSION} to ${TARGET} completed"
