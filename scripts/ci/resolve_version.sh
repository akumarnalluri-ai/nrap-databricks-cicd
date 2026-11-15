#!/usr/bin/env bash
# =============================================================================
# resolve_version.sh
# Turns the requested version into a concrete, verified Git tag.
#
#   REQUESTED_VERSION = v1.2.0    -> that exact tag
#                     = latest    -> highest semantic-version tag (v*)
#                     = previous  -> last version that ran SUCCESSFULLY in this
#                                    environment before the one live now
#                                    (used by the rollback workflow)
#
# Also records the version currently deployed (PREVIOUS_VERSION) so the
# deploy workflow can auto-rollback to it if the new release fails.
#
# Inputs (env): REQUESTED_VERSION, JOB_NAME, REPO_DIR, REQUIRE_TAG_ON_MAIN, MAIN_BRANCH
# Outputs     : version, commit, previous_version  (GitHub step outputs)
# =============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

REQUESTED="${REQUESTED_VERSION:-latest}"
REQUESTED="${REQUESTED//[[:space:]]/}"
REPO_DIR="${REPO_DIR:?REPO_DIR not set}"
cd "$REPO_DIR" || die "Cannot cd to $REPO_DIR"

git fetch --tags --force --quiet origin || warn "Could not refresh tags from origin; using tags from checkout"

list_recent_tags() {
  log "Most recent tags in this repository:"
  git tag -l --sort=-creatordate | head -n 15 | sed 's/^/    /' | tee -a "$LOG_DIR/pipeline.log"
}

CURRENT="$(get_deployed_version "$JOB_NAME" || true)"
log "Version currently deployed to '${JOB_NAME}': ${CURRENT:-<none - first deployment>}"

case "${REQUESTED,,}" in
  latest)
    # Highest strict release tag (vMAJOR.MINOR.PATCH); pre-release / feature
    # tags are ignored. When REQUIRE_TAG_ON_MAIN=true only tags on main count.
    merged_args=()
    is_true "${REQUIRE_TAG_ON_MAIN:-false}" && merged_args=(--merged "origin/${MAIN_BRANCH:-main}")
    VERSION="$(git tag -l 'v*' "${merged_args[@]}" --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -n1 || true)"
    [[ -n "$VERSION" ]] || die "No release tags (vX.Y.Z) found - create a release first (e.g. v1.0.0)"
    log "'latest' resolved to ${VERSION}"
    ;;
  previous)
    VERSION="$(find_previous_good_version "$JOB_NAME" "$CURRENT" || true)"
    [[ -n "$VERSION" ]] || die "Could not find an earlier successfully-validated version for ${JOB_NAME}. Re-run and type the version explicitly."
    log "'previous' resolved to ${VERSION} (last successful version before ${CURRENT:-none})"
    ;;
  *)
    VERSION="$REQUESTED"
    ;;
esac

# Only safe tag characters (also keeps artifact names valid).
[[ "$VERSION" =~ ^[A-Za-z0-9._-]+$ ]] || die "Invalid version '$VERSION' - use a tag such as v1.2.0"

if ! git rev-parse -q --verify "refs/tags/${VERSION}^{commit}" >/dev/null; then
  list_recent_tags
  die "Tag '${VERSION}' does not exist in this repository"
fi
COMMIT="$(git rev-list -n1 "refs/tags/${VERSION}")"

if is_true "${REQUIRE_TAG_ON_MAIN:-false}"; then
  branch="${MAIN_BRANCH:-main}"
  git merge-base --is-ancestor "$COMMIT" "origin/${branch}" \
    || die "Tag ${VERSION} (${COMMIT:0:12}) is not on origin/${branch}. Only releases cut from ${branch} may be deployed to this environment."
  log "Tag ${VERSION} is on origin/${branch}"
fi

# Nothing to roll back to if we are re-deploying the same version.
PREVIOUS=""
[[ -n "$CURRENT" && "$CURRENT" != "$VERSION" ]] && PREVIOUS="$CURRENT"

log "Deploying version ${VERSION} (commit ${COMMIT:0:12}); auto-rollback target: ${PREVIOUS:-<none>}"
to_output version "$VERSION"
to_output commit "$COMMIT"
to_output previous_version "$PREVIOUS"
to_env RELEASE_VERSION "$VERSION"
to_env RELEASE_COMMIT "$COMMIT"
to_env PREVIOUS_VERSION "$PREVIOUS"
