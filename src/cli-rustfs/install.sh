#!/usr/bin/env bash
# Installs rc, RustFS's S3 client (https://github.com/rustfs/cli), from the
# release's rustfs-cli_<version>_<arch>.deb, checked against the consumer's
# sha256. The package puts the statically linked binary at /usr/bin/rc. The
# version and sha come from the feature options, the image environment
# (CLI_RUSTFS_*) or the pins file; see NOTES.md and
# docs/adrs/0002-resolve-pins-from-option-env-or-pins-file-with-no-defaults.md.
set -euo pipefail
# shellcheck source=install-lib.sh
. "$(dirname "$0")/install-lib.sh"

il_require_root
il_resolve_pin CLI_RUSTFS true

# The asset names use Debian's arch names, which il_arch prints.
arch="$(il_arch)"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
# apt reads a local .deb as the _apt user; a 0700 directory makes it fall
# back to root with a warning.
chmod 0755 "$tmp"

asset="rustfs-cli_${IL_VERSION}_${arch}.deb"
url="https://github.com/rustfs/cli/releases/download/v${IL_VERSION}/${asset}"
il_fetch_verified "$url" "$IL_SHA256" "${tmp}/${asset}"

# apt-get install, not dpkg -i, so any Depends a future release declares
# are resolved (0.1.36 declares none). The lists are removed afterwards, as
# il_apt_install does.
export DEBIAN_FRONTEND=noninteractive
apt-get update || {
    echo "cli-rustfs: apt-get update failed" >&2
    exit 1
}
apt-get install -y --no-install-recommends "${tmp}/${asset}" || {
    echo "cli-rustfs: apt-get install failed: ${asset}" >&2
    exit 1
}
rm -rf /var/lib/apt/lists/*

installed="$(dpkg-query -W -f='${Version}' rustfs-cli)"
if [ "$installed" != "$IL_VERSION" ]; then
    echo "cli-rustfs: rustfs-cli ${installed} is installed, expected ${IL_VERSION}" >&2
    exit 1
fi

echo "cli-rustfs: installed $(/usr/bin/rc --version)"
