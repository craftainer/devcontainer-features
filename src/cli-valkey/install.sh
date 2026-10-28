#!/usr/bin/env bash
# Installs valkey-cli (https://valkey.io) as /usr/local/bin/valkey-cli from
# upstream's Ubuntu 24.04 (noble) binary tarball for this arch, checked
# against the consumer's sha256. Only bin/valkey-cli is extracted; the
# tarball's server, sentinel and benchmark binaries are not installed. The
# version and sha come from the feature options, the image environment
# (CLI_VALKEY_*) or the pins file; see NOTES.md and
# docs/adrs/0002-resolve-pins-from-option-env-or-pins-file-with-no-defaults.md.
set -euo pipefail
# shellcheck source=install-lib.sh
. "$(dirname "$0")/install-lib.sh"

il_require_root
il_resolve_pin CLI_VALKEY true

arch="$(il_arch)"
case "$arch" in
    amd64) asset_arch=x86_64 ;;
    arm64) asset_arch=arm64 ;;
esac

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# The noble build is used on every supported distro: it needs glibc 2.38
# and OpenSSL 3 (libssl.so.3, libcrypto.so.3), which Debian 13 and Ubuntu
# 24.04 both ship in their base images. Upstream's other Linux build
# (jammy) targets older systems this collection doesn't support.
dir="valkey-${IL_VERSION}-noble-${asset_arch}"
asset="${dir}.tar.gz"
url="https://download.valkey.io/releases/${asset}"
il_fetch_verified "$url" "$IL_SHA256" "${tmp}/${asset}"

tar -xzf "${tmp}/${asset}" -C "$tmp" --no-same-owner "${dir}/bin/valkey-cli"
il_install_bin "${tmp}/${dir}/bin/valkey-cli" valkey-cli

echo "cli-valkey: installed $(/usr/local/bin/valkey-cli --version)"
