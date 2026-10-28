#!/usr/bin/env bash
# Tests scripts/collection-release.sh against throwaway git repos: the
# first release, each bump level, new and removed features, no change,
# re-runs (HEAD already tagged, an older push after a newer release),
# release tags off HEAD's history (ignored, or an error on a collision),
# invalid feature ids, a version that went down, and tags that aren't
# release tags.
#
# Self-contained: needs only bash, git and jq. Run by the
# collection-release prek hook; run it by hand from anywhere.
set -euo pipefail

script="$(cd "$(dirname "$0")" && pwd)/collection-release.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failures=0
# A literal backtick, for the Markdown code spans in the expected notes.
bt=$'\x60'
current=""

fail() {
    echo "FAIL [${current}]: $*" >&2
    failures=$((failures + 1))
}

g() {
    git -c user.name=test -c user.email=test@example.invalid \
        -c commit.gpgsign=false -c tag.gpgsign=false -c core.hooksPath=/dev/null \
        -c init.defaultBranch=main "$@"
}

# Starts a fresh repo for case $1.
new_repo() {
    current="$1"
    repo="${work}/${1}"
    mkdir -p "$repo"
    g -C "$repo" init --quiet
}

# Writes src/$1/devcontainer-feature.json with version $2.
feature() {
    mkdir -p "${repo}/src/$1"
    printf '{\n  "id": "%s",\n  "version": "%s",\n  "name": "%s"\n}\n' "$1" "$2" "$1" \
        >"${repo}/src/$1/devcontainer-feature.json"
}

commit() {
    g -C "$repo" add -A
    g -C "$repo" commit --quiet --allow-empty -m "$1"
}

tag() { g -C "$repo" tag "$1"; }

# Runs the script in the repo; sets $out (stdout), $notes and $rc.
run() {
    notes="${repo}.notes.md"
    rm -f "$notes"
    rc=0
    out="$(cd "$repo" && GITHUB_SERVER_URL=https://github.com GITHUB_REPOSITORY=Craftainer/devcontainer-features \
        "$script" "$notes" 2>"${repo}.log")" || rc=$?
}

expect_tag() {
    if [ "$rc" -ne 0 ]; then
        fail "exit ${rc}, expected 0; stderr: $(cat "${repo}.log")"
        return
    fi
    if [ "$out" != "tag=$1" ]; then
        fail "stdout '${out}', expected 'tag=$1'"
    fi
}

expect_notes() {
    if [ ! -f "$notes" ]; then
        fail "no notes file"
        return
    fi
    if ! grep -qF -- "$1" "$notes"; then
        fail "notes lack: $1"$'\n'"--- notes ---"$'\n'"$(cat "$notes")"
    fi
}

expect_no_notes() {
    if [ -f "$notes" ]; then
        fail "wrote a notes file although there is no release"
    fi
}

# A repo released as v1.0.0 with features a and b at 1.0.0.
released_base() {
    new_repo "$1"
    feature a 1.0.0
    feature b 1.0.0
    commit initial
    tag v1.0.0
}

# --- first release ---
new_repo first-release
feature a 1.0.0
feature b 1.2.3
echo x >"${repo}/README.md"
commit initial
g -C "$repo" tag a_v1.0.0 # devcontainers/action's per-feature tag is ignored
run
expect_tag v1.0.0
expect_notes "The collection's first release."
expect_notes "| [${bt}a@1.0.0${bt}](https://github.com/Craftainer/devcontainer-features/tree/v1.0.0/src/a) | new | ${bt}ghcr.io/craftainer/devcontainer-features/a:1${bt} |"
expect_notes "| [${bt}b@1.2.3${bt}](https://github.com/Craftainer/devcontainer-features/tree/v1.0.0/src/b) | new | ${bt}ghcr.io/craftainer/devcontainer-features/b:1${bt} |"
expect_notes "Reference a feature in ${bt}devcontainer.json${bt} as ${bt}ghcr.io/craftainer/devcontainer-features/<id>:<major>${bt}"

# --- patch ---
released_base patch
feature a 1.0.1
commit "fix a"
run
expect_tag v1.0.1
expect_notes "compared with v1.0.0"
expect_notes "| [${bt}a@1.0.1${bt}](https://github.com/Craftainer/devcontainer-features/tree/v1.0.1/src/a) | 1.0.0 → 1.0.1 |"
expect_notes "| [${bt}b@1.0.0${bt}](https://github.com/Craftainer/devcontainer-features/tree/v1.0.1/src/b) | unchanged |"

# --- minor (the highest bump wins over a patch) ---
released_base minor
feature a 1.1.0
feature b 1.0.1
commit "feat a, fix b"
run
expect_tag v1.1.0
expect_notes "${bt}a@1.1.0${bt}"
expect_notes '| 1.0.0 → 1.1.0 |'
expect_notes '| 1.0.0 → 1.0.1 |'

# --- major ---
released_base major
feature a 2.0.0
feature b 1.1.0
commit "break a"
run
expect_tag v2.0.0
expect_notes "| 1.0.0 → 2.0.0 | ${bt}ghcr.io/craftainer/devcontainer-features/a:2${bt} |"

# --- new feature ---
released_base new-feature
feature c 1.0.0
commit "add c"
run
expect_tag v1.1.0
expect_notes "| [${bt}c@1.0.0${bt}](https://github.com/Craftainer/devcontainer-features/tree/v1.1.0/src/c) | new |"

# --- removed feature (beats a new one) ---
released_base removed-feature
rm -r "${repo}/src/b"
feature c 1.0.0
commit "drop b, add c"
run
expect_tag v2.0.0
expect_notes "- ${bt}b${bt} (last 1.0.0, in v1.0.0)"
if grep -qF "${bt}b@" "$notes" 2>/dev/null; then fail "removed feature b is listed in the table"; fi

# --- no change: a non-version edit makes no release ---
released_base no-change
echo "# notes" >"${repo}/src/a/NOTES.md"
commit "docs only"
run
expect_tag ""
expect_no_notes

# --- previous = the highest SemVer tag, not the latest by name or date ---
new_repo highest-tag
feature a 1.9.0
commit one
tag v1.9.0
feature a 1.10.0
commit two
tag v1.10.0
g -C "$repo" tag v2.0     # not X.Y.Z
g -C "$repo" tag v3.0.0-rc.1 # a pre-release isn't a release tag
feature a 1.10.1
commit three
run
expect_tag v1.10.1

# --- existing tag: HEAD already tagged (a job re-run, or a release that
# failed after its tag was made) reuses the tag, so the workflow can create
# a missing release ---
released_base existing-tag
feature a 1.0.1
commit "fix a"
tag v1.0.1
run
expect_tag v1.0.1
expect_notes "compared with v1.0.0"
expect_notes '| 1.0.0 → 1.0.1 |'

# --- a release tag off HEAD's history doesn't stop releases ---
released_base stray-tag
g -C "$repo" checkout --quiet -b side
feature a 9.0.0
commit "side branch"
tag v9.0.0
g -C "$repo" checkout --quiet main
feature a 1.0.1
commit "fix a"
run
expect_tag v1.0.1
expect_notes "compared with v1.0.0"

# --- the computed tag already exists off HEAD's history: an error ---
released_base tag-collision
g -C "$repo" checkout --quiet -b side
feature b 1.0.1
commit "side branch"
tag v1.0.1
g -C "$repo" checkout --quiet main
feature a 1.0.1
commit "fix a"
run
if [ "$rc" -eq 0 ]; then fail "exit 0 although v1.0.1 exists off HEAD's history"; fi
if ! grep -qF "tag v1.0.1 already exists on a commit outside HEAD's history" "${repo}.log"; then
    fail "no collision message; stderr: $(cat "${repo}.log")"
fi

# --- an invalid feature id fails instead of being word-split ---
released_base invalid-id
feature "foo bar" 1.0.0
commit "bad id"
run
if [ "$rc" -eq 0 ]; then fail "exit 0 for feature id 'foo bar'"; fi
if ! grep -qF "invalid feature id 'foo bar'" "${repo}.log"; then
    fail "no invalid-id message; stderr: $(cat "${repo}.log")"
fi

# --- existing tag: re-run of an older push after a newer release ---
released_base stale-rerun
feature a 1.0.1
commit "fix a"
older="$(g -C "$repo" rev-parse HEAD)"
feature a 1.0.2
commit "fix a again"
tag v1.0.2
g -C "$repo" checkout --quiet "$older"
run
expect_tag ""
expect_no_notes

# --- a version that went down fails ---
released_base downgrade
feature a 0.9.0
commit "oops"
run
if [ "$rc" -eq 0 ]; then fail "exit 0 for a version that went down"; fi
if ! grep -qF "a: version went down from 1.0.0 (v1.0.0) to 0.9.0" "${repo}.log"; then
    fail "no downgrade message; stderr: $(cat "${repo}.log")"
fi

# --- a malformed version fails ---
released_base bad-version
feature a 1.1
commit "bad"
run
if [ "$rc" -eq 0 ]; then fail "exit 0 for version 1.1"; fi

if [ "$failures" -ne 0 ]; then
    echo "test-collection-release: ${failures} failure(s)" >&2
    exit 1
fi
echo "test-collection-release: all cases pass"
