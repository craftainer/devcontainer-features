#!/usr/bin/env bash
# Installs opencode (https://github.com/anomalyco/opencode, formerly
# sst/opencode) as /usr/local/bin/opencode from the release tarball for this
# arch, checked against the consumer's sha256. The version and sha come from
# the feature options, the image environment (CLI_OPENCODE_*) or the pins
# file; see NOTES.md and
# docs/adrs/0002-resolve-pins-from-option-env-or-pins-file-with-no-defaults.md.
#
# The asset is the one the official installer (https://opencode.ai/install)
# picks on a glibc Linux CPU with AVX2:
# https://github.com/anomalyco/opencode/releases/download/v<version>/opencode-linux-{x64,arm64}.tar.gz,
# holding a single top-level "opencode" binary. The release's other Linux
# assets, opencode-linux-x64-baseline (x64 CPUs without AVX2) and the
# *-musl builds (Alpine), are out of scope.
set -euo pipefail
# shellcheck source=install-lib.sh
. "$(dirname "$0")/install-lib.sh"

il_require_root
il_resolve_pin CLI_OPENCODE true

arch="$(il_arch)"
case "$arch" in
    amd64) platform=linux-x64 ;;
    arm64) platform=linux-arm64 ;;
esac

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

asset="opencode-${platform}.tar.gz"
url="https://github.com/anomalyco/opencode/releases/download/v${IL_VERSION}/${asset}"
il_fetch_verified "$url" "$IL_SHA256" "${tmp}/${asset}"

tar -xzf "${tmp}/${asset}" -C "$tmp" --no-same-owner opencode
il_install_bin "${tmp}/opencode" opencode

# opencode keeps its config in ~/.config/opencode and its data, including
# the provider credentials in auth.json, in ~/.local/share/opencode.
# Consumers who keep that state across rebuilds mount named volumes there
# (NOTES.md). Docker seeds an empty named volume with the ownership and
# mode of the image directory it is mounted on, and creates that directory
# root-owned when the image doesn't have it. So both are created here,
# owned by the remote user with mode 0700: without them, a fresh volume
# comes up owned by root and opencode can't write to it.
il_user_state_dir .config/opencode .local/share/opencode

# opencode creates its XDG directories under $HOME, and $TMPDIR/opencode,
# on every start, even for --version. Run it against a throwaway home and
# TMPDIR (a separate one: $tmp/opencode is the extracted binary) so this
# root-run check leaves nothing in root's (or anyone's) home directory.
# Every variable that points opencode's state elsewhere is unset too, so a
# path the image sets (say OPENCODE_CONFIG_DIR under the remote user's home)
# isn't created root-owned here.
mkdir -m 0700 "${tmp}/home" "${tmp}/run"
installed="$(env -u XDG_CONFIG_HOME -u XDG_DATA_HOME -u XDG_CACHE_HOME -u XDG_STATE_HOME \
    -u XDG_RUNTIME_DIR -u OPENCODE_CONFIG_DIR -u OPENCODE_CONFIG \
    HOME="${tmp}/home" TMPDIR="${tmp}/run" OPENCODE_DISABLE_AUTOUPDATE=1 \
    /usr/local/bin/opencode --version)"
echo "cli-opencode: installed opencode ${installed}"
