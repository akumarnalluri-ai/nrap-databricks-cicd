#!/usr/bin/env bash
# =============================================================================
# find_placeholders.sh - list every  __REPLACE_...__  placeholder still in the
# repo, with file and line number. Run from the repo root:  bash scripts/find_placeholders.sh
# Commented-out placeholders (optional features) are listed separately.
# =============================================================================
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

echo "Active placeholders (must be replaced before use):"
grep -rnIP --exclude-dir=.git --exclude-dir=docs --exclude=find_placeholders.sh '^[^#]*__REPLACE_[A-Z0-9_]*__' . || echo "  none"

echo
echo "Optional placeholders (inside comments - only needed if you enable that feature):"
grep -rnIP --exclude-dir=.git --exclude-dir=docs --exclude=find_placeholders.sh '#.*__REPLACE_[A-Z0-9_]*__' . || echo "  none"
