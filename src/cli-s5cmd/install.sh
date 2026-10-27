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

echo "cli-s5cmd: installed $(/usr/local/bin/s5cmd version)"
