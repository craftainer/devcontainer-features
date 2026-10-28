#!/usr/bin/env bash
# This collection's side of template-base's release contract (docs/TEMPLATE.md,
# "Release: a Makefile contract"), called by the Makefile's targets; see
# docs/adrs/0004-collection-github-releases.md. Run from the repo root.
#
#   release-features.sh build    package every src/<id>/ into dist/ with the
#                                Dev Container CLI: devcontainer-feature-<id>.tgz
#                                per feature plus devcontainer-collection.json
#   release-features.sh assets   check dist/ holds exactly those files, then list it
#   release-features.sh check    validate every devcontainer-feature.json, run
#                                the feature-options and install-lib drift
#                                checks, and check dist/ against src/
#   release-features.sh publish  run the checks above, then push every feature
#                                to the OCI registry with
#                                `devcontainer features publish`, only for a
#                                full release (no pre-release suffix)
#
# publish authenticates with the OCI_REGISTRY_USERNAME/OCI_REGISTRY_PASSWORD
# secrets when either is set (both are then required). With neither set and
# OCI_REGISTRY=ghcr.io, it uses the job's GITHUB_TOKEN as GITHUB_ACTOR, which
# needs release.yml's build job to grant `packages: write` (template-sync
# brings that in from the template-base release that adds it). Any other
# registry needs the secrets.
#
# The Dev Container CLI is the version pinned in
# scripts/develop.d/10-devcontainer-cli.sh (one pin, which Renovate bumps). A
# `devcontainer` on PATH (or DEVCONTAINER_CLI) is used when it is that version;
# otherwise the pinned version is installed from npm into a temporary prefix
# (the host runner has Node but not the CLI).
#
# The packaged .tgz files are what `devcontainer features publish` pushes, but
# the CLI can't publish a prebuilt package: `publish` packages src/ again from
# the same commit.
set -euo pipefail
export LC_ALL=C

DIST="${DIST:-dist}"
CLI_PIN_FILE=scripts/develop.d/10-devcontainer-cli.sh
# The CLI's own output file names (features package).
COLLECTION_FILE=devcontainer-collection.json

die() {
    echo "release-features: $*" >&2
    exit 1
}

tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT

# Feature ids from src/<id>/devcontainer-feature.json, in C-locale order,
# with the same id rule as features.yml's discover job. Fails when there are
# none.
IDS=()
load_ids() {
    local meta id
    shopt -s nullglob
    for meta in src/*/devcontainer-feature.json; do
        id="${meta#src/}" id="${id%%/*}"
        [[ "$id" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "invalid feature id '${id}' (${meta})"
        IDS+=("$id")
    done
    [ "${#IDS[@]}" -gt 0 ] || die "no features under src/"
}

# Sets DEVCONTAINER to a `devcontainer` binary at the pinned version.
DEVCONTAINER=
resolve_cli() {
    local want have prefix attempt
    want="$(sed -n 's/^DEVCONTAINER_CLI_VERSION=\([0-9][0-9.]*\)$/\1/p' "$CLI_PIN_FILE")"
    [ -n "$want" ] || die "no DEVCONTAINER_CLI_VERSION=<x.y.z> line in ${CLI_PIN_FILE}"

    DEVCONTAINER="${DEVCONTAINER_CLI:-$(command -v devcontainer || true)}"
    if [ -n "$DEVCONTAINER" ]; then
        have="$("$DEVCONTAINER" --version 2>/dev/null || true)"
        if [ "$have" = "$want" ]; then
            return 0
        fi
        [ -z "${DEVCONTAINER_CLI:-}" ] || die "DEVCONTAINER_CLI=${DEVCONTAINER_CLI} is version '${have}', expected ${want}"
        echo "release-features: devcontainer on PATH is version '${have}', not ${want}; installing ${want}" >&2
    fi

    command -v npm >/dev/null 2>&1 || die "npm is needed to install @devcontainers/cli@${want}"
    prefix="${tmp_root}/cli"
    # Bounded retries for the registry's transient errors on shared CI IPs.
    for attempt in 1 2 3; do
        if npm install --prefix "$prefix" --cache "${tmp_root}/npm-cache" \
            --ignore-scripts --no-audit --no-fund --no-update-notifier \
            "@devcontainers/cli@${want}" >&2; then
            break
        fi
        [ "$attempt" -lt 3 ] || die "npm install @devcontainers/cli@${want} failed 3 times"
        sleep $((attempt * 5))
    done
    DEVCONTAINER="${prefix}/node_modules/.bin/devcontainer"
    have="$("$DEVCONTAINER" --version)"
    [ "$have" = "$want" ] || die "installed devcontainer is version '${have}', expected ${want}"
}

# Fails unless every devcontainer-feature.json is a valid feature: an object
# whose id matches its folder, with a name, a SemVer version, and options of
# a supported type whose default matches it. The full schema check is
# devcontainers/action's, on every pull request (features.yml's validate).
validate_metadata() {
    local id meta status=0 errors line
    for id in "${IDS[@]}"; do
        meta="src/${id}/devcontainer-feature.json"
        if ! errors="$(jq -r --arg id "$id" '
            def semver: test("^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?(\\+[0-9A-Za-z.-]+)?$");
            if type != "object" then "not a JSON object"
            else
              (if .id != $id then "id \(.id | tojson) does not match its folder \($id)" else empty end),
              (if (.name | type) != "string" or .name == "" then "name is missing or empty" else empty end),
              (if (.version | type) != "string" or (.version | semver | not) then "version \(.version | tojson) is not SemVer" else empty end),
              (if has("options") and (.options | type) != "object" then "options is not an object"
               else (.options // {} | to_entries[]
                 | .key as $k | .value
                 | if type != "object" then "option \($k) is not an object"
                   elif (.type == "boolean") then
                     (if has("default") and (.default | type) != "boolean" then "option \($k): default is not a boolean" else empty end)
                   elif (.type == "string") then
                     (if has("default") and (.default | type) != "string" then "option \($k): default is not a string" else empty end)
                   else "option \($k): type \(.type | tojson) is not boolean or string" end)
               end)
            end' "$meta" 2>&1)"; then
            echo "release-features: ${meta}: not valid JSON (${errors})" >&2
            status=1
            continue
        fi
        if [ -n "$errors" ]; then
            while IFS= read -r line; do
                echo "release-features: ${meta}: ${line}" >&2
            done <<<"$errors"
            status=1
        fi
        [ -f "src/${id}/install.sh" ] || { echo "release-features: src/${id}/install.sh is missing" >&2; status=1; }
    done
    return "$status"
}

# Fails unless dist/ holds, for the features in src/, exactly one
# devcontainer-feature-<id>.tgz each (whose metadata names that id and
# src/'s version) and a collection file listing the same ids and versions.
check_dist() {
    local id want got status=0 f expected actual
    [ -d "$DIST" ] || die "${DIST}/ is missing; run 'make build' first"

    expected="$( { printf '%s\n' "$COLLECTION_FILE"; printf 'devcontainer-feature-%s.tgz\n' "${IDS[@]}"; } | sort)"
    actual="$(find "$DIST" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort)"
    if [ "$expected" != "$actual" ]; then
        echo "release-features: ${DIST}/ doesn't hold exactly the packaged features:" >&2
        diff <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") | sed -n 's/^</  missing:/p; s/^>/  unexpected:/p' >&2 || true
        return 1
    fi

    for id in "${IDS[@]}"; do
        want="$(jq -r '.version' "src/${id}/devcontainer-feature.json")"
        f="${DIST}/devcontainer-feature-${id}.tgz"
        # The CLI's .tgz is a plain (uncompressed) tar, the OCI layer itself.
        got="$(tar -xOf "$f" ./devcontainer-feature.json 2>/dev/null | jq -r '"\(.id)@\(.version)"' 2>/dev/null || true)"
        if [ "$got" != "${id}@${want}" ]; then
            echo "release-features: ${f} holds '${got:-no readable devcontainer-feature.json}', expected ${id}@${want}" >&2
            status=1
        fi
    done

    expected="$(for id in "${IDS[@]}"; do
        printf '%s@%s\n' "$id" "$(jq -r '.version' "src/${id}/devcontainer-feature.json")"
    done | sort)"
    actual="$(jq -r '.features[] | "\(.id)@\(.version)"' "${DIST}/${COLLECTION_FILE}" 2>/dev/null | sort || true)"
    if [ "$expected" != "$actual" ]; then
        echo "release-features: ${DIST}/${COLLECTION_FILE} lists [$(tr '\n' ' ' <<<"$actual")], expected [$(tr '\n' ' ' <<<"$expected")]" >&2
        status=1
    fi
    return "$status"
}

cmd_build() {
    local out
    load_ids
    resolve_cli
    out="${tmp_root}/package"
    "$DEVCONTAINER" features package src --output-folder "$out" --log-level info
    mkdir -p "$DIST"
    # A rebuild replaces this script's own files, so a removed feature's old
    # package doesn't linger; anything else in dist/ is left alone.
    rm -f "$DIST"/devcontainer-feature-*.tgz "${DIST:?}/${COLLECTION_FILE}"
    cp "$out"/devcontainer-feature-*.tgz "$out/${COLLECTION_FILE}" "$DIST"/
}

cmd_assets() {
    load_ids
    check_dist
    echo "Release assets in ${DIST}/:"
    ls -l "$DIST"
}

# The release check proper: release-check runs it, and publish runs it first
# too, since publish runs in build's job, before release-check, and a pushed
# feature version can't be replaced. Needs load_ids first.
run_checks() {
    local status=0
    command -v jq >/dev/null 2>&1 || die "jq is required"
    validate_metadata || status=1
    scripts/check-feature-options.sh || status=1
    scripts/check-install-lib-drift.sh || status=1
    check_dist || status=1
    [ "$status" -eq 0 ] || die "release check failed"
    echo "release-features: ${#IDS[@]} features valid; ${DIST}/ matches src/."
}

cmd_check() {
    load_ids
    run_checks
}

cmd_publish() {
    local version namespace registry_user registry_token auth_source
    version="${RELEASE_VERSION:-${RELEASE_TAG:-}}"
    version="${version#v}"

    # alpha/beta/rc build and attach their packages to the GitHub Release but
    # push nothing: a pushed feature version is what consumers resolve.
    if [[ "$version" == *-* ]]; then
        echo "release-features: ${version} is a pre-release; skipping the registry publish (only a full release publishes features)."
        return 0
    fi
    if [ -z "${OCI_REGISTRY:-}" ]; then
        if [ -n "$version" ]; then
            echo "::warning::OCI_REGISTRY is not set, so full release ${version} publishes no features; set the OCI_REGISTRY variable (ghcr.io needs no secrets; any other registry needs the OCI_REGISTRY_USERNAME/OCI_REGISTRY_PASSWORD secrets; README.md, \"Releasing the collection\"), then re-run this run's build job to publish them."
        fi
        echo "release-features: OCI_REGISTRY not set -- skipping publish."
        return 0
    fi
    [ -n "$version" ] || die "RELEASE_VERSION (or RELEASE_TAG) is not set"
    [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "'${version}' is not a full release version (x.y.z)"

    # Explicit secrets win; on ghcr.io without them, the job's GITHUB_TOKEN.
    if [ -n "${OCI_REGISTRY_USERNAME:-}" ] || [ -n "${OCI_REGISTRY_PASSWORD:-}" ]; then
        [ -n "${OCI_REGISTRY_USERNAME:-}" ] || die "OCI_REGISTRY is set but the OCI_REGISTRY_USERNAME secret is empty"
        [ -n "${OCI_REGISTRY_PASSWORD:-}" ] || die "OCI_REGISTRY is set but the OCI_REGISTRY_PASSWORD secret is empty"
        registry_user="$OCI_REGISTRY_USERNAME" registry_token="$OCI_REGISTRY_PASSWORD"
        auth_source="the OCI_REGISTRY_USERNAME/OCI_REGISTRY_PASSWORD secrets"
    elif [ "$OCI_REGISTRY" = ghcr.io ]; then
        [ -n "${GITHUB_TOKEN:-}" ] || die "OCI_REGISTRY is ghcr.io and the OCI_REGISTRY_USERNAME/OCI_REGISTRY_PASSWORD secrets are empty, but GITHUB_TOKEN is not set either; release.yml's build job needs \`permissions: packages: write\` and GITHUB_TOKEN in its env (template-sync it from the template-base release that adds it), or set both secrets"
        [ -n "${GITHUB_ACTOR:-}" ] || die "OCI_REGISTRY is ghcr.io and publish would use GITHUB_TOKEN, but GITHUB_ACTOR is not set"
        registry_user="$GITHUB_ACTOR" registry_token="$GITHUB_TOKEN"
        auth_source="GITHUB_TOKEN as ${GITHUB_ACTOR} (needs packages: write on release.yml's build job)"
    else
        die "OCI_REGISTRY is ${OCI_REGISTRY}, not ghcr.io, so the OCI_REGISTRY_USERNAME and OCI_REGISTRY_PASSWORD secrets are required; both are empty"
    fi
    # DEVCONTAINERS_OCI_AUTH is "registry|user|token[,...]"; a '|' or ',' in
    # a value would split it in the wrong place.
    case "${OCI_REGISTRY}${registry_user}${registry_token}" in
        *'|'* | *,*) die "OCI_REGISTRY and the registry user and token must not contain '|' or ','" ;;
    esac

    namespace="${OCI_IMAGE_NAME:-${GITHUB_REPOSITORY:-}}"
    [ -n "$namespace" ] || die "set OCI_IMAGE_NAME or GITHUB_REPOSITORY (owner/repo) for the feature namespace"
    namespace="$(printf '%s' "$namespace" | tr '[:upper:]' '[:lower:]')"

    # publish runs once per release-arches leg; the collection is pushed once.
    # With more than one arch, the legs would race on the same feature tags.
    [ "${RELEASE_ARCH:-amd64}" = amd64 ] || die "publish runs on the amd64 leg only (RELEASE_ARCH=${RELEASE_ARCH}); release-arches must print [\"amd64\"]"

    load_ids
    run_checks
    resolve_cli
    echo "release-features: publishing release ${version}'s features to ${OCI_REGISTRY}/${namespace}/<id> (versions already in the registry are skipped), authenticating with ${auth_source}."
    # The credentials reach the CLI through the environment only, never its
    # command line. GITHUB_TOKEN is dropped either way, so the only
    # credential the CLI sees is the one chosen above, in DEVCONTAINERS_OCI_AUTH.
    DEVCONTAINERS_OCI_AUTH="${OCI_REGISTRY}|${registry_user}|${registry_token}" \
        env -u GITHUB_TOKEN -u OCI_REGISTRY_PASSWORD \
        "$DEVCONTAINER" features publish src --registry "$OCI_REGISTRY" --namespace "$namespace" --log-level info
}

case "${1:-}" in
    build) cmd_build ;;
    assets) cmd_assets ;;
    check) cmd_check ;;
    publish) cmd_publish ;;
    *) die "usage: $0 build|assets|check|publish" ;;
esac
