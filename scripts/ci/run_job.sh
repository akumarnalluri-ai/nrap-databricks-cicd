#!/usr/bin/env bash
# =============================================================================
# run_job.sh <bundle-dir> <target> <version> <job-resource-key> [log-name]
# Runs the deployed job and WAITS for it to finish. The job's last task
# (03_validate_deployment) performs the data checks, so a non-zero exit here
# means the release failed validation in Databricks.
# Output: run_url (GitHub step output)
# =============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

BUNDLE_DIR="${1:?bundle dir required}"
TARGET="${2:?target required}"
VERSION="${3:?version required}"
JOB_KEY="${4:?job resource key required}"
LOG_NAME="${5:-run}"

cd "$BUNDLE_DIR" || die "Cannot cd to $BUNDLE_DIR"
log "===== Running job '${JOB_KEY}' on ${TARGET} (version ${VERSION}) ====="

rc=0
run_logged "$LOG_NAME" databricks bundle run -t "$TARGET" --var="release_version=${VERSION}" "$JOB_KEY" || rc=$?

# The CLI prints "Run URL: https://<host>/?o=...#job/<id>/run/<run_id>"
run_url="$(grep -Eo 'https://[^[:space:]]+' "$LOG_DIR/${LOG_NAME}.log" | grep -E 'run' | tail -n1 || true)"
[[ -n "$run_url" ]] && log "Run URL: $run_url" && to_output run_url "$run_url"

[[ $rc -eq 0 ]] || die "Job run FAILED for ${VERSION} on ${TARGET} - open the run URL above for the failing task output"
log "Job run SUCCEEDED for ${VERSION} on ${TARGET}"
