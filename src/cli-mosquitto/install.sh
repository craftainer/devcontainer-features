#!/usr/bin/env bash
# Installs the Eclipse Mosquitto MQTT clients (mosquitto_pub, mosquitto_sub,
# mosquitto_rr) from apt at an exact upstream version, e.g. 2.0.22. On
# Debian they come from repo.mosquitto.org, whose signing key is pinned
# below by fingerprint; on Ubuntu from the distro's own archive. The
# version comes from the feature options, the image environment
# (CLI_MOSQUITTO_VERSION) or the pins file; there is no sha: apt checks
# every package against the repository's signature. Which versions exist
# depends on the distro. See NOTES.md and
# docs/adrs/0003-pin-apt-installed-clis-by-upstream-version-with-a-verified-repo-key.md.
set -euo pipefail
# shellcheck source=install-lib.sh
. "$(dirname "$0")/install-lib.sh"

# repo.mosquitto.org's signing key, https://repo.mosquitto.org/debian/README.txt.
MOSQUITTO_KEY_URL=https://repo.mosquitto.org/debian/mosquitto-repo.gpg
MOSQUITTO_FINGERPRINT=8277CCB49EC5B595F2D2C71361611AE430993623
MOSQUITTO_DISTS_URL=https://repo.mosquitto.org/debian/dists/

il_require_root
il_resolve_version CLI_MOSQUITTO

# Read in subshells: sourcing /etc/os-release here would set VERSION,
# which is the version option's variable (see il_resolve_version).
os_id="$(. /etc/os-release && echo "${ID:-}")"
os_id_like="$(. /etc/os-release && echo "${ID_LIKE:-}")"
codename="$(. /etc/os-release && echo "${VERSION_CODENAME:-}")"

case "$os_id" in
    debian)
        if ! [[ "$codename" =~ ^[a-z]+$ ]]; then
            echo "cli-mosquitto: cannot read a release codename from /etc/os-release" \
                "(VERSION_CODENAME='${codename}'); repo.mosquitto.org's suites are named after it" >&2
            exit 1
        fi
        # il_apt_add_repo exits on failure, so it runs in a subshell to
        # name the likely cause here.
        if ! (il_apt_add_repo mosquitto "$MOSQUITTO_KEY_URL" "$MOSQUITTO_FINGERPRINT" \
            "https://repo.mosquitto.org/debian ${codename} main"); then
            echo "cli-mosquitto: cannot add repo.mosquitto.org's '${codename}' suite." \
                "If the error above is about the suite, repo.mosquitto.org doesn't" \
                "build for ${codename}; the releases it serves are listed at" \
                "${MOSQUITTO_DISTS_URL}" >&2
            exit 1
        fi
        ;;
    ubuntu)
        # Ubuntu's own archive (universe); no repository is added.
        ;;
    *)
        echo "cli-mosquitto: unsupported distribution ID='${os_id}' (ID_LIKE='${os_id_like}')" \
            "in /etc/os-release; supported: debian (from repo.mosquitto.org) and" \
            "ubuntu (from its own archive)" >&2
        exit 1
        ;;
esac

il_apt_install_pinned mosquitto-clients "$IL_VERSION"

# Each client prints "<tool> version <v> running on libmosquitto <v>." for
# --version and exits 1 (upstream's client code returns 1 after printing
# the version), so only the output is checked; a client that can't start
# prints no such line.
for tool in mosquitto_pub mosquitto_sub mosquitto_rr; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "cli-mosquitto: ${tool} is not on PATH after installing mosquitto-clients" >&2
        exit 1
    fi
    out="$("$tool" --version 2>&1)" || true
    if [ "$out" != "${tool} version ${IL_VERSION} running on libmosquitto ${IL_VERSION}." ]; then
        echo "cli-mosquitto: ${tool} --version reports '${out}'," \
            "not ${IL_VERSION} on libmosquitto ${IL_VERSION}" >&2
        exit 1
    fi
done
echo "cli-mosquitto: installed mosquitto-clients $(dpkg-query -W -f='${Version}' mosquitto-clients): ${out}"
