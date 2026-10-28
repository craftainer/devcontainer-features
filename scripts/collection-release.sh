#!/usr/bin/env bash
# Works out the collection's next GitHub Release (v<x.y.z>) for HEAD and
# writes its notes (see
# docs/adrs/0004-collection-github-releases.md).
#
# Usage: scripts/collection-release.sh NOTES_FILE
#
# Prints "tag=v<x.y.z>" on stdout when HEAD needs a release (and writes the
# notes to NOTES_FILE), or "tag=" when it doesn't, so features.yml can
# append stdout to $GITHUB_OUTPUT. Everything else goes to stderr.
#
# - Previous release: the highest v<x.y.z> tag (strict SemVer, no
#   pre-release) that is an ancestor of HEAD; with none, the release is
#   v1.0.0. Release tags on commits off HEAD's history are ignored.
# - Bump: each src/<id>/devcontainer-feature.json "version" at HEAD against
#   the same file at the previous tag. A major bump or a removed feature
#   bumps major; else a minor bump or a new feature bumps minor; else a
#   patch bump bumps patch; no change means no release.
# - Idempotent, so a re-run of the job is safe:
#   - a v<x.y.z> tag already on HEAD is reused (tag=<it>, notes against the
#     previous release), so the workflow can create a release that is
#     missing for an existing tag and skip one that exists;
#   - no release when a release tag on a later commit already contains
#     HEAD (a re-run of an older push after a newer release).
#   The computed tag existing elsewhere (off HEAD's history) is an error.
# - Repo for links and the OCI namespace: $GITHUB_SERVER_URL and
#   $GITHUB_REPOSITORY, defaulting to github.com/craftainer/devcontainer-features.
#
# Reads git objects only (HEAD and the tags), never the working tree.
# Run from the repo root.
set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "usage: $0 NOTES_FILE" >&2
    exit 2
fi
notes_file="$1"
server="${GITHUB_SERVER_URL:-https://github.com}"
repo="${GITHUB_REPOSITORY:-craftainer/devcontainer-features}"
namespace="ghcr.io/$(printf '%s' "$repo" | tr '[:upper:]' '[:lower:]')"

log() { echo "collection-release: $*" >&2; }
no_release() {
    log "$*"
    echo "tag="
    exit 0
}

semver_re='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'

# Prints the "version" of the devcontainer-feature.json at $1 (a
# <rev>:<path> git object), or fails when it isn't X.Y.Z.
feature_version() {
    local v
    v="$(git show "$1" | jq -r '.version // empty')" || return 1
    if ! [[ "$v" =~ $semver_re ]]; then
        log "version '${v}' in ${1} is not X.Y.Z"
        return 1
    fi
    printf '%s' "$v"
}

# Prints the feature ids at revision $1, one per line: every src/<id>/ that
# has a devcontainer-feature.json. Fails on an id features.yml's discover
# job would reject, so callers can split the list on whitespace safely.
feature_ids() {
    local ids id
    ids="$(git ls-tree -r --name-only "$1" -- src/ \
        | sed -n 's|^src/\([^/]*\)/devcontainer-feature\.json$|\1|p' \
        | sort)" || return 1
    while IFS= read -r id; do
        [ -n "$id" ] || continue
        if ! [[ "$id" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
            log "invalid feature id '${id}' at ${1}"
            return 1
        fi
        printf '%s\n' "$id"
    done <<<"$ids"
}

# Prints major, minor, patch or none for X.Y.Z $1 -> $2; fails when $2 is
# lower than $1.
bump_kind() {
    local a1 a2 a3 b1 b2 b3
    IFS=. read -r a1 a2 a3 <<<"$1"
    IFS=. read -r b1 b2 b3 <<<"$2"
    if [ "$b1" -ne "$a1" ]; then
        [ "$b1" -gt "$a1" ] && echo major && return
    elif [ "$b2" -ne "$a2" ]; then
        [ "$b2" -gt "$a2" ] && echo minor && return
    elif [ "$b3" -ne "$a3" ]; then
        [ "$b3" -gt "$a3" ] && echo patch && return
    else
        echo none && return
    fi
    return 1
}

rank() {
    case "$1" in
        major) echo 3 ;;
        minor) echo 2 ;;
        patch) echo 1 ;;
        *) echo 0 ;;
    esac
}

# Prints the release tags (v<x.y.z>) among the tag names on stdin, highest
# first.
release_tags() {
    { grep -E '^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$' || true; } \
        | sort -t. -k1.2,1nr -k2,2nr -k3,3nr
}

# The highest release tag on HEAD itself, if any (a re-run, or a tag pushed
# by hand): reused, so its release is created if it's missing.
head_tag="$(git tag --points-at HEAD | release_tags | sed -n 1p)"

# A release tag on a later commit that contains HEAD: this is a re-run of
# an older push, and that release already covers HEAD.
if [ -z "$head_tag" ] && [ -n "$(git tag --contains HEAD | release_tags)" ]; then
    no_release "a later release already contains HEAD (a re-run of an older push?); nothing to do"
fi

# The previous release: the highest release tag in HEAD's history, other
# than the ones on HEAD.
prev="$(
    { git tag --merged HEAD | grep -vxF -f <(git tag --points-at HEAD) || true; } \
        | release_tags | sed -n 1p
)"

declare -A old_v=() new_v=() change=()
level=none

head_ids="$(feature_ids HEAD)"
for id in $head_ids; do
    new_v[$id]="$(feature_version "HEAD:src/${id}/devcontainer-feature.json")"
done
if [ -n "$prev" ]; then
    prev_ids="$(feature_ids "$prev")"
    for id in $prev_ids; do
        old_v[$id]="$(feature_version "${prev}:src/${id}/devcontainer-feature.json")"
    done
fi

if [ "${#new_v[@]}" -eq 0 ]; then
    no_release "no features at HEAD; nothing to release"
fi

raise() {
    if [ "$(rank "$1")" -gt "$(rank "$level")" ]; then level="$1"; fi
}

for id in "${!new_v[@]}"; do
    if [ -z "${old_v[$id]:-}" ]; then
        change[$id]="new"
        raise minor
        continue
    fi
    if ! kind="$(bump_kind "${old_v[$id]}" "${new_v[$id]}")"; then
        log "${id}: version went down from ${old_v[$id]} (${prev}) to ${new_v[$id]}"
        exit 1
    fi
    if [ "$kind" != none ]; then
        change[$id]="${old_v[$id]} → ${new_v[$id]}"
        raise "$kind"
    fi
done
removed=()
for id in "${!old_v[@]}"; do
    if [ -z "${new_v[$id]:-}" ]; then
        removed+=("$id")
        raise major
    fi
done

if [ -n "$head_tag" ]; then
    tag="$head_tag"
    log "HEAD is already tagged ${tag}; reusing it so a missing release gets created"
elif [ -z "$prev" ]; then
    tag=v1.0.0
else
    IFS=. read -r M m p <<<"${prev#v}"
    case "$level" in
        none) no_release "no feature version changed since ${prev}; no release" ;;
        major) tag="v$((M + 1)).0.0" ;;
        minor) tag="v${M}.$((m + 1)).0" ;;
        patch) tag="v${M}.${m}.$((p + 1))" ;;
    esac
fi

# Not on HEAD, not in its history and not containing it (all handled
# above): a tag elsewhere that a release here would collide with.
if [ -z "$head_tag" ] && git rev-parse --verify --quiet "refs/tags/${tag}" >/dev/null; then
    log "tag ${tag} already exists on a commit outside HEAD's history; resolve it by hand"
    exit 1
fi

if [ -n "$prev" ]; then
    log "${prev} -> ${tag} (${level} change)"
else
    log "first release: ${tag}"
fi

{
    if [ -n "$prev" ]; then
        echo "Feature versions in this release, compared with ${prev}."
    else
        echo "The collection's first release."
    fi
    echo
    echo "| Feature | Change | Reference |"
    echo "| --- | --- | --- |"
    for id in $(printf '%s\n' "${!new_v[@]}" | sort); do
        major="${new_v[$id]%%.*}"
        echo "| [\`${id}@${new_v[$id]}\`](${server}/${repo}/tree/${tag}/src/${id}) | ${change[$id]:-unchanged} | \`${namespace}/${id}:${major}\` |"
    done
    if [ "${#removed[@]}" -gt 0 ]; then
        echo
        echo "Removed:"
        echo
        for id in $(printf '%s\n' "${removed[@]}" | sort); do
            echo "- \`${id}\` (last ${old_v[$id]}, in ${prev})"
        done
    fi
    echo
    echo "Reference a feature in \`devcontainer.json\` as \`${namespace}/<id>:<major>\` (or pin \`<major>.<minor>\` or \`<major>.<minor>.<patch>\`); each feature is versioned on its own, and this release's tag only marks the collection as a whole."
} >"$notes_file"

echo "tag=${tag}"
