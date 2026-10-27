#!/usr/bin/env bash
# Fails when a src/<id>/devcontainer-feature.json declares its pin options
# in a way that lets an inherited value leak into the install:
#
# - In a feature whose install.sh sources install-lib.sh, each of these
#   options it declares must have "default": "" (exactly the empty
#   string): version, sha256, sha256_amd64, sha256_arm64 and pins_file
#   (il_resolve_pin's options), plus certs, urls and sha256s (ssl-ca's,
#   which it resolves the same way without il_resolve_pin).
# - Every feature that declares "version" must also declare "pins_file".
#
# The Dev Container CLI writes a declared option to devcontainer-features.env
# only through its default when the user doesn't set it, and sources that
# file with set -a before install.sh runs. An option without a default is
# not written, so a VERSION (or SHA256, ...) inherited from the base
# image's ENV or exported by an earlier feature would be read as the
# option; a non-empty default would be a bundled pin. See
# docs/adrs/0002-resolve-pins-from-option-env-or-pins-file-with-no-defaults.md.
#
# Passes when there is no src/. Run from the repo root.
set -euo pipefail

pin_options='["version","sha256","sha256_amd64","sha256_arm64","pins_file","certs","urls","sha256s"]'

shopt -s nullglob
metas=(src/*/devcontainer-feature.json)
# Without jq every file below would be reported as invalid JSON.
if [ "${#metas[@]}" -gt 0 ] && ! command -v jq >/dev/null 2>&1; then
    echo "check-feature-options: jq is required but not installed (apt-get install jq)" >&2
    exit 1
fi

status=0
for meta in "${metas[@]}"; do
    dir="${meta%/devcontainer-feature.json}"
    if ! jq -e '(.options // {}) | type == "object"' "$meta" >/dev/null 2>&1; then
        echo "check-feature-options: ${meta}: not valid JSON, or \"options\" is not an object" >&2
        status=1
        continue
    fi
    if [ -f "${dir}/install.sh" ] \
        && grep -Eq '^[[:space:]]*(\.|source)[[:space:]].*install-lib\.sh' "${dir}/install.sh"; then
        bad="$(jq -r --argjson names "$pin_options" '
            (.options // {}) | to_entries[]
            | select(.key as $k | $names | index($k))
            | select((.value | type == "object" and has("default") and .default == "") | not)
            | .key' "$meta")"
        for opt in $bad; do
            echo "check-feature-options: ${meta}: option \"${opt}\" must have \"default\": \"\" (without one an inherited ${opt^^} leaks through; any other value is a bundled pin)" >&2
            status=1
        done
    fi
    if jq -e '(.options // {}) | has("version") and (has("pins_file") | not)' "$meta" >/dev/null; then
        echo "check-feature-options: ${meta}: declares \"version\" but not \"pins_file\"; add \"pins_file\": {\"type\": \"string\", \"default\": \"\"}" >&2
        status=1
    fi
done
exit "$status"
