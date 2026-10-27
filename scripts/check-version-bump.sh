#!/usr/bin/env bash
# Fails when a feature under src/<id>/ changed without raising the
# "version" in its devcontainer-feature.json above the base ref's.
#
# devcontainers/action never republishes a version that already exists, so
# a change without a bump would silently never ship (see
# docs/adrs/0001-one-collection-repo-released-with-devcontainers-action.md).
#
# - Base ref: $VERSION_BUMP_BASE (default origin/main). Changes are taken
#   from its merge base with HEAD to the working tree, staged or not, plus
#   untracked files, so it works in a pre-commit hook and in CI alike.
# - A feature absent from the base ref is new and passes; a deleted feature
#   passes. src/<id>/README.md alone is ignored: devcontainers/action's
#   generate-docs rewrites it after a publish, without a bump.
# - When the base ref doesn't exist (a shallow CI checkout, or a clone
#   with no origin/main yet), it skips with a notice, unless
#   VERSION_BUMP_REQUIRE_BASE=1, which makes that an error. features.yml
#   runs it that way on pull requests, with full history, so the check is
#   enforced in CI even where the prek run inside checks.yml skips it.
#
# Run from the repo root.
set -euo pipefail

base="${VERSION_BUMP_BASE:-origin/main}"

if ! git rev-parse --verify --quiet "${base}^{commit}" >/dev/null; then
    if [ "${VERSION_BUMP_REQUIRE_BASE:-}" = 1 ]; then
        echo "check-version-bump: base ref '${base}' not found; fetch it (e.g. git fetch origin main, or actions/checkout with fetch-depth: 0)" >&2
        exit 1
    fi
    echo "check-version-bump: base ref '${base}' not found; skipping (features.yml enforces this check on pull requests)"
    exit 0
fi

if ! merge_base="$(git merge-base "$base" HEAD)"; then
    echo "check-version-bump: no merge base between '${base}' and HEAD" >&2
    exit 1
fi

# Prints X.Y.Z from a devcontainer-feature.json read on stdin, or fails.
feature_version() {
    local v
    v="$(jq -r '.version // empty')" || return 1
    if ! printf '%s' "$v" | grep -Eq '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'; then
        echo "check-version-bump: version '${v}' is not X.Y.Z" >&2
        return 1
    fi
    printf '%s' "$v"
}

# Succeeds when X.Y.Z $1 is strictly greater than X.Y.Z $2.
version_gt() {
    local a1 a2 a3 b1 b2 b3
    IFS=. read -r a1 a2 a3 <<<"$1"
    IFS=. read -r b1 b2 b3 <<<"$2"
    if [ "$a1" -ne "$b1" ]; then [ "$a1" -gt "$b1" ]; return; fi
    if [ "$a2" -ne "$b2" ]; then [ "$a2" -gt "$b2" ]; return; fi
    [ "$a3" -gt "$b3" ]
}

changed="$(
    {
        git diff --name-only "$merge_base" -- src/
        git ls-files --others --exclude-standard -- src/
    } | sort -u
)"

ids="$(
    printf '%s\n' "$changed" \
        | grep -E '^src/[^/]+/.' \
        | grep -Ev '^src/[^/]+/README\.md$' \
        | cut -d/ -f2 \
        | sort -u
)" || true

status=0
for id in $ids; do
    meta="src/${id}/devcontainer-feature.json"
    if [ ! -f "$meta" ]; then
        echo "check-version-bump: ${id}: removed, nothing to publish"
        continue
    fi
    if ! git cat-file -e "${base}:${meta}" 2>/dev/null; then
        echo "check-version-bump: ${id}: new feature (not on ${base})"
        continue
    fi
    if ! new="$(feature_version <"$meta")"; then
        echo "check-version-bump: ${id}: cannot read the version in ${meta}" >&2
        status=1
        continue
    fi
    if ! old="$(git show "${base}:${meta}" | feature_version)"; then
        echo "check-version-bump: ${id}: cannot read the version in ${base}:${meta}" >&2
        status=1
        continue
    fi
    if version_gt "$new" "$old"; then
        echo "check-version-bump: ${id}: ${old} -> ${new}"
    else
        echo "check-version-bump: ${id}: src/${id}/ changed but its version ${new} is not above ${old} on ${base}; bump \"version\" in ${meta}" >&2
        status=1
    fi
done
exit "$status"
