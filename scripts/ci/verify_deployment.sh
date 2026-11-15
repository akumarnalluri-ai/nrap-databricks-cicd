#!/usr/bin/env bash
# =============================================================================
# verify_deployment.sh <version> <job-name> [expect-successful-run=true|false]
# Independent post-deployment checks against the workspace (not the bundle):
#   1. the job exists
#   2. the job's release_version tag equals the version just deployed
#   3. every notebook referenced by the job exists in the workspace
#   4. (optional) the job's latest completed run SUCCEEDED for this version
# Outputs: job_id, job_url
# =============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

VERSION="${1:?version required}"
JOB_NAME="${2:?job name required}"
EXPECT_RUN="${3:-false}"
failures=0
check() { if [[ "$1" == "PASS" ]]; then log "[PASS] $2"; else warn "[FAIL] $2"; failures=$((failures + 1)); fi; }

log "===== Verifying deployment of ${VERSION} (${JOB_NAME}) ====="

JOB_ID="$(find_job_id "$JOB_NAME")"
if [[ -z "$JOB_ID" ]]; then
  check FAIL "Job '${JOB_NAME}' exists"
  die "Verification failed - job not found"
fi
check PASS "Job '${JOB_NAME}' exists (job_id=${JOB_ID})"
JOB_JSON="$(databricks jobs get "$JOB_ID" --output json)"
echo "$JOB_JSON" > "$LOG_DIR/deployed_job_${JOB_NAME}.json"

tagged="$(jq -r '.settings.tags.release_version // empty' <<<"$JOB_JSON")"
[[ "$tagged" == "$VERSION" ]] \
  && check PASS "Job tag release_version=${tagged}" \
  || check FAIL "Job tag release_version is '${tagged}', expected '${VERSION}'"

while IFS= read -r nb; do
  [[ -z "$nb" ]] && continue
  if databricks workspace get-status "$nb" >/dev/null 2>&1; then
    check PASS "Notebook present: $nb"
  else
    check FAIL "Notebook missing: $nb"
  fi
done < <(jq -r '.settings.tasks[]?.notebook_task.notebook_path // empty' <<<"$JOB_JSON")

if is_true "$EXPECT_RUN"; then
  last_run="$(databricks jobs list-runs --job-id "$JOB_ID" --completed-only --output json \
    | jq -c '(if type=="array" then . else (.runs // []) end) | .[0] // empty')"
  if [[ -z "$last_run" ]]; then
    check FAIL "A completed job run exists"
  else
    run_id="$(jq -r '.run_id' <<<"$last_run")"
    result="$(jq -r '.state.result_state // .status.termination_details.code // "UNKNOWN"' <<<"$last_run")"
    run_version="$(databricks jobs get-run "$run_id" --output json \
      | jq -r '(.job_parameters // [])[] | select(.name=="release_version") | (.value // .default // empty)' | head -n1)"
    [[ "$result" == "SUCCESS" ]] \
      && check PASS "Latest run ${run_id} result=${result}" \
      || check FAIL "Latest run ${run_id} result=${result}"
    [[ "$run_version" == "$VERSION" ]] \
      && check PASS "Latest run executed release ${run_version}" \
      || check FAIL "Latest run executed release '${run_version}', expected '${VERSION}'"
  fi
fi

to_output job_id "$JOB_ID"
to_output job_url "${DATABRICKS_HOST%/}/jobs/${JOB_ID}"

[[ $failures -eq 0 ]] || die "Deployment verification failed (${failures} check(s))"
log "Deployment verification passed for ${VERSION}"
