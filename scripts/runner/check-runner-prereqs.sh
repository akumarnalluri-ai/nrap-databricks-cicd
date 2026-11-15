#!/usr/bin/env bash
# =============================================================================
# check-runner-prereqs.sh - run on the runner VM (as the runner user) to
# confirm it can do a deployment. Optionally tests Databricks login:
#   DATABRICKS_HOST=https://... DATABRICKS_TOKEN=dapi... bash check-runner-prereqs.sh
# =============================================================================
set -uo pipefail
ok=0; bad=0
pass() { echo "  [OK]   $*"; ok=$((ok + 1)); }
fail() { echo "  [FAIL] $*"; bad=$((bad + 1)); }

echo "Tools:"
for t in bash git jq curl python3 databricks; do
  if command -v "$t" >/dev/null 2>&1; then pass "$t -> $(command -v "$t")"; else fail "$t not found"; fi
done
command -v databricks >/dev/null 2>&1 && echo "         $(databricks --version)"

echo "Network (HTTPS 443):"
for url in https://github.com https://api.github.com https://objects.githubusercontent.com; do
  if curl -fsS -o /dev/null --max-time 10 "$url"; then pass "$url"; else fail "$url unreachable"; fi
done
if [[ -n "${DATABRICKS_HOST:-}" ]]; then
  if curl -sS -o /dev/null --max-time 10 "$DATABRICKS_HOST"; then pass "$DATABRICKS_HOST"; else fail "$DATABRICKS_HOST unreachable"; fi
fi

if [[ -n "${DATABRICKS_HOST:-}" ]] && command -v databricks >/dev/null 2>&1; then
  echo "Databricks login:"
  if user=$(databricks current-user me --output json 2>/dev/null | jq -r .userName); then
    pass "authenticated as $user"
  else
    fail "could not authenticate to $DATABRICKS_HOST"
  fi
fi

echo; echo "Result: $ok passed, $bad failed"
[[ $bad -eq 0 ]]
