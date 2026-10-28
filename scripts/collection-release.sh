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
#   pre-release); with none, the release is v1.0.0.
# - Bump: each src/<id>/devcontainer-feature.json "version" at HEAD against
#   the same file at the previous tag. A major bump or a removed feature
#   bumps major; else a minor bump or a new feature bumps minor; else a
#   patch bump bumps patch; no change means no release.
# - Idempotent, so a re-run of the job is safe: no release when a v<x.y.z>
#   tag already points at HEAD, when the computed tag already exists, or
#   when the previous tag isn't an ancestor of HEAD (a re-run of an older
#   push after a newer release).
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
# has a devcontainer-feature.json.
feature_ids() {
    git ls-tree -r --name-only "$1" -- src/ \
        | sed -n 's|^src/\([^/]*\)/devcontainer-feature\.json$|\1|p' \
        | sort
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

# Release tags, highest first.
release_tags="$(
    git tag --list 'v*' \
        | grep -E '^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$' \
        | sort -t. -k1.2,1nr -k2,2nr -k3,3nr
)" || true

head_sha="$(git rev-parse HEAD)"
for t in $release_tags; do
    if [ "$(git rev-parse "${t}^{commit}")" = "$head_sha" ]; then
        no_release "HEAD is already released as ${t}; nothing to do"
    fi
done

prev="$(printf '%s\n' "$release_tags" | head -n 1)"
if [ -n "$prev" ] && ! git merge-base --is-ancestor "$prev" HEAD; then
    no_release "the latest release ${prev} isn't an ancestor of HEAD (a re-run of an older push?); nothing to do"
fi

declare -A old_v=() new_v=() change=()
level=none

for id in $(feature_ids HEAD); do
    new_v[$id]="$(feature_version "HEAD:src/${id}/devcontainer-feature.json")"
done
if [ -n "$prev" ]; then
    for id in $(feature_ids "$prev"); do
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

if [ -z "$prev" ]; then
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

if git rev-parse --verify --quiet "refs/tags/${tag}" >/dev/null; then
    no_release "tag ${tag} already exists; nothing to do"
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
