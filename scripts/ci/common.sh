#!/usr/bin/env bash
# =============================================================================
# common.sh - shared helpers sourced by every scripts/ci/*.sh script.
# Provides: logging, GitHub output helpers, and small Databricks CLI lookups.
# Requires: bash 4+, jq, databricks CLI (>= 0.218).
# =============================================================================
set -Eeuo pipefail

LOG_DIR="${LOG_DIR:-${RUNNER_TEMP:-/tmp}/deploy-logs}"
mkdir -p "$LOG_DIR"

ts()   { date -u +%Y-%m-%dT%H:%M:%SZ; }
log()  { printf '%s [INFO]  %s\n' "$(ts)" "$*" | tee -a "$LOG_DIR/pipeline.log"; }
warn() { printf '%s [WARN]  %s\n' "$(ts)" "$*" | tee -a "$LOG_DIR/pipeline.log"; echo "::warning::$*"; }
die()  { printf '%s [ERROR] %s\n' "$(ts)" "$*" | tee -a "$LOG_DIR/pipeline.log" >&2; echo "::error::$*"; exit 1; }

# Print a clear error line (with script + line number) for any unexpected failure.
trap 'rc=$?; echo "::error::${BASH_SOURCE[0]##*/} failed at line ${LINENO} (exit ${rc})"' ERR

# run_logged <log-name> <command...>
# Runs a command, streams output to the console AND to $LOG_DIR/<log-name>.log,
# and returns the command's real exit code.
run_logged() {
  local name="$1"; shift
  log "Running: $*"
  set +e
  "$@" 2>&1 | tee -a "$LOG_DIR/${name}.log"
  local rc=${PIPESTATUS[0]}
  set -e
  if [[ $rc -ne 0 ]]; then
    printf '%s [ERROR] Command failed (exit %s): %s\n' "$(ts)" "$rc" "$*" | tee -a "$LOG_DIR/pipeline.log" >&2
  fi
  return "$rc"
}

# Write KEY=VALUE to the GitHub job environment / step outputs (no-op locally).
to_env()    { echo "$1=$2" >> "${GITHUB_ENV:-/dev/null}"; }
to_output() { echo "$1=$2" >> "${GITHUB_OUTPUT:-/dev/null}"; }

is_true() { [[ "${1,,}" == "true" ]]; }

# Windows runners: native jq.exe / databricks.exe can emit CRLF line endings,
# which corrupt values (job ids, versions) in bash. Strip carriage returns.
jq() { command jq "$@" | tr -d '\r'; }

# --- Databricks lookups ------------------------------------------------------

# find_job_id <job-name>  -> prints the job_id, or nothing if the job doesn't exist
find_job_id() {
  databricks jobs list --name "$1" --output json 2>/dev/null \
    | jq -r 'if type=="array" then . else (.jobs // []) end | .[0].job_id // empty'
}

# get_deployed_version <job-name> -> release_version tag of the deployed job
get_deployed_version() {
  local id; id="$(find_job_id "$1")"
  [[ -z "$id" ]] && return 0
  databricks jobs get "$id" --output json | jq -r '.settings.tags.release_version // empty'
}

# find_previous_good_version <job-name> <exclude-version>
# Walks the job's most recent SUCCESSFUL runs (newest first) and prints the
# first release_version that differs from <exclude-version>.
find_previous_good_version() {
  local job_name="$1" exclude="$2" id run_ids rid v
  id="$(find_job_id "$job_name")"
  [[ -z "$id" ]] && return 0
  run_ids="$(databricks jobs list-runs --job-id "$id" --completed-only --output json \
    | jq -r '(if type=="array" then . else (.runs // []) end)
             | map(select((.state.result_state // "") == "SUCCESS"
                          or (.status.termination_details.code // "") == "SUCCESS"))
             | .[0:25] | .[].run_id')"
  for rid in $run_ids; do
    v="$(databricks jobs get-run "$rid" --output json \
      | jq -r '(.job_parameters // [])[] | select(.name=="release_version") | (.value // .default // empty)' \
      | head -n1)"
    if [[ -n "$v" && "$v" != "$exclude" && "$v" != "local-dev" ]]; then
      echo "$v"; return 0
    fi
  done
}
