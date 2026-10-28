#!/usr/bin/env bash
# Installs valkey-cli (https://valkey.io) as /usr/local/bin/valkey-cli from
# upstream's Ubuntu 24.04 (noble) binary tarball for this arch, checked
# against the consumer's sha256. Only bin/valkey-cli and the license notice
# (share/LICENSE, as /usr/local/share/doc/valkey-cli/LICENSE) are extracted;
# the tarball's server, sentinel and benchmark binaries are not installed. The
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
# 24.04 both package (OpenSSL 3 is installed below when it's missing).
# Upstream's other Linux build
# (jammy) targets older systems this collection doesn't support.
dir="valkey-${IL_VERSION}-noble-${asset_arch}"
asset="${dir}.tar.gz"
url="https://download.valkey.io/releases/${asset}"
il_fetch_verified "$url" "$IL_SHA256" "${tmp}/${asset}"

tar -xzf "${tmp}/${asset}" -C "$tmp" --no-same-owner "${dir}/bin/valkey-cli"
il_install_bin "${tmp}/${dir}/bin/valkey-cli" valkey-cli

# Valkey is BSD-3-Clause, whose notice must accompany the binary; it comes
# from the same verified tarball. A release without it installs the binary
# anyway.
if tar -xzf "${tmp}/${asset}" -C "$tmp" --no-same-owner "${dir}/share/LICENSE" 2>/dev/null; then
    install -D -m 0644 "${tmp}/${dir}/share/LICENSE" /usr/local/share/doc/valkey-cli/LICENSE
else
    echo "cli-valkey: warning: ${asset} has no share/LICENSE; no license notice installed" >&2
fi

# valkey-cli links libssl.so.3 and libcrypto.so.3. The debian:13 and
# ubuntu:24.04 images have them today only as a dependency of other
# packages (coreutils, apt), so install them here when they're missing
# rather than rely on that; libssl3t64 is OpenSSL 3's package name on both
# Debian 13 and Ubuntu 24.04. grep without -q reads all of
# ldconfig's output, so pipefail can't see a SIGPIPE.
if ! ldconfig -p | grep -F 'libssl.so.3 ' >/dev/null; then
    il_apt_install libssl3t64
fi

# A separate assignment, so a binary that can't start (missing glibc 2.38
# or libssl.so.3) fails the install under set -e instead of being masked
# inside echo's arguments.
installed="$(/usr/local/bin/valkey-cli --version)"
echo "cli-valkey: installed ${installed}"
