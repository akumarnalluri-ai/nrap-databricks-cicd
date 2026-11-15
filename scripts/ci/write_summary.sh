#!/usr/bin/env bash
# =============================================================================
# write_summary.sh
# Writes the deployment record to the GitHub run summary page (always runs).
# Reads env vars set by the workflow and earlier steps.
# =============================================================================
set -uo pipefail

out="${GITHUB_STEP_SUMMARY:-/dev/stdout}"
status="${JOB_STATUS:-unknown}"
icon="✅"; [[ "$status" != "success" ]] && icon="❌"

rollback_line="not needed"
case "${ROLLBACK_OUTCOME:-}" in
  success) rollback_line="✅ rolled back to ${PREVIOUS_VERSION}" ;;
  failure) rollback_line="❌ auto-rollback to ${PREVIOUS_VERSION} FAILED - manual action required" ;;
  *) [[ "$status" != "success" ]] && rollback_line="not performed (no previous version or disabled)" ;;
esac

{
  echo "## ${icon} Databricks ${DEPLOY_MODE:-deploy}: ${RELEASE_VERSION:-${REQUESTED_VERSION:-?}} → ${TARGET_ENV:-?}"
  echo
  echo "| Item | Value |"
  echo "|---|---|"
  echo "| Result | **${status}** |"
  echo "| Environment / bundle target | ${TARGET_ENV:-?} / ${BUNDLE_TARGET:-?} |"
  echo "| Requested version | ${REQUESTED_VERSION:-?} |"
  echo "| Deployed version | ${RELEASE_VERSION:-not resolved} |"
  echo "| Commit | ${RELEASE_COMMIT:-n/a} |"
  echo "| Version live before this run | ${PREVIOUS_VERSION:-none} |"
  echo "| Auto-rollback | ${rollback_line} |"
  echo "| Databricks job | ${JOB_URL:-n/a} |"
  echo "| Job run | ${RUN_URL:-not run} |"
  echo "| Deployed by (GitHub) | ${GITHUB_ACTOR:-?} |"
  echo "| Databricks identity | ${DEPLOY_IDENTITY:-?} |"
  echo "| Reason | ${DEPLOY_REASON:-n/a} |"
  echo "| Runner | ${RUNNER_NAME:-?} |"
  echo
  echo "Full execution logs are attached to this run as an artifact."
} >> "$out"
