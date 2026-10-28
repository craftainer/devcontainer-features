#!/usr/bin/env bash
# Installs s5cmd (https://github.com/peak/s5cmd) as /usr/local/bin/s5cmd
# from the release tarball for this arch, checked against the consumer's
# sha256. The version and sha come from the feature options, the image
# environment (CLI_S5CMD_*) or the pins file; see NOTES.md and
# docs/adrs/0002-resolve-pins-from-option-env-or-pins-file-with-no-defaults.md.
set -euo pipefail
# shellcheck source=install-lib.sh
. "$(dirname "$0")/install-lib.sh"

il_require_root
il_resolve_pin CLI_S5CMD true
# The release tag adds the v itself; a pinned "v2.3.0" would fetch tag
# vv2.3.0 and fail as an unexplained 404.
case "$IL_VERSION" in
    [vV]*)
        echo "cli-s5cmd: version '${IL_VERSION}' must not start with v (use ${IL_VERSION#[vV]})" >&2
        exit 1
        ;;
esac

arch="$(il_arch)"
case "$arch" in
    amd64) asset_arch=64bit ;;
    arm64) asset_arch=arm64 ;;
esac

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

asset="s5cmd_${IL_VERSION}_Linux-${asset_arch}.tar.gz"
url="https://github.com/peak/s5cmd/releases/download/v${IL_VERSION}/${asset}"
il_fetch_verified "$url" "$IL_SHA256" "${tmp}/${asset}"

tar -xzf "${tmp}/${asset}" -C "$tmp" --no-same-owner s5cmd
il_install_bin "${tmp}/s5cmd" s5cmd

# s5cmd is MIT-licensed; its notice comes from the same verified tarball.
# A release without it (none known) installs the binary anyway.
if tar -xzf "${tmp}/${asset}" -C "$tmp" --no-same-owner LICENSE 2>/dev/null; then
    install -D -m 0644 "${tmp}/LICENSE" /usr/local/share/doc/s5cmd/LICENSE
else
    echo "cli-s5cmd: warning: ${asset} has no LICENSE; no license notice installed" >&2
fi

echo "cli-s5cmd: installed $(/usr/local/bin/s5cmd version)"
