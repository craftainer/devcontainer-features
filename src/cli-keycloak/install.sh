#!/usr/bin/env bash
# Installs a Keycloak admin CLI as kcadm, in one of two flavors (see
# NOTES.md; they share the name, not the syntax):
#
# - official: kcadm.sh and its client jars from Keycloak's release
#   tarball (https://github.com/keycloak/keycloak/releases), checked
#   against the consumer's sha256, in /usr/local/lib/keycloak-cli, with
#   kcadm and kcadm.sh on PATH; plus the distro's headless JRE unless
#   install_jre is false. The version and sha come from the feature
#   options, the image environment (CLI_KEYCLOAK_*) or the pins file; see
#   docs/adrs/0002-resolve-pins-from-option-env-or-pins-file-with-no-defaults.md.
# - rest: the craftainer family's curl wrapper around the Admin REST API
#   (kcadm-rest.sh, kcadm METHOD PATH [JSON]); no download, so no pin.
set -euo pipefail
# shellcheck source=install-lib.sh
. "$(dirname "$0")/install-lib.sh"

# Keycloak 26 runs on Java 21 or newer.
min_java=21
lib_dir=/usr/local/lib/keycloak-cli

il_require_root

# The flavor resolves like a pin, without the pairing: the flavor option,
# then CLI_KEYCLOAK_FLAVOR in the image environment, then the pins file;
# official when none sets it.
#
# Reading the pins file relies on install-lib's private _il_pins_get (the
# library has no public single-key getter yet). A library refactor must
# keep it or update this feature; the rest_pins_file scenario fails if it
# breaks.
flavor="${FLAVOR:-}"
flavor_from="the flavor feature option"
if [ -z "$flavor" ] && [ -n "${CLI_KEYCLOAK_FLAVOR:-}" ]; then
    flavor="$CLI_KEYCLOAK_FLAVOR"
    flavor_from="CLI_KEYCLOAK_FLAVOR in the image environment"
fi
pins_file="${PINS_FILE:-/etc/devcontainer-features/pins.env}"
if [ -z "$flavor" ] && [ -f "$pins_file" ]; then
    if [ ! -r "$pins_file" ]; then
        echo "cli-keycloak: pins file ${pins_file} is not readable" >&2
        exit 1
    fi
    flavor="$(_il_pins_get "$pins_file" CLI_KEYCLOAK_FLAVOR)"
    flavor_from="CLI_KEYCLOAK_FLAVOR in the pins file ${pins_file}"
fi
if [ -z "$flavor" ]; then
    flavor=official
    flavor_from="the default"
fi
case "$flavor" in
    official | rest) ;;
    *)
        echo "cli-keycloak: invalid flavor '${flavor}' from ${flavor_from} (expected official or rest)" >&2
        exit 1
        ;;
esac
echo "cli-keycloak: flavor ${flavor} (from ${flavor_from})"

if [ "$flavor" = rest ]; then
    pkgs=()
    command -v curl >/dev/null 2>&1 || pkgs+=(curl)
    [ -f /etc/ssl/certs/ca-certificates.crt ] || pkgs+=(ca-certificates)
    command -v python3 >/dev/null 2>&1 || pkgs+=(python3)
    if [ "${#pkgs[@]}" -gt 0 ]; then
        il_apt_install "${pkgs[@]}"
    fi
    il_install_bin "$(dirname "$0")/kcadm-rest.sh" kcadm
    echo "cli-keycloak: installed the rest wrapper as /usr/local/bin/kcadm"
    exit 0
fi

install_jre="${INSTALL_JRE:-true}"
case "$install_jre" in
    true | false) ;;
    *)
        echo "cli-keycloak: install_jre must be true or false, not '${install_jre}'" >&2
        exit 1
        ;;
esac

il_resolve_pin CLI_KEYCLOAK false

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

asset="keycloak-${IL_VERSION}.tar.gz"
url="https://github.com/keycloak/keycloak/releases/download/${IL_VERSION}/${asset}"
il_fetch_verified "$url" "$IL_SHA256" "${tmp}/${asset}"

# Only what kcadm.sh needs: itself and bin/client/ (the admin CLI jar and
# client/lib/). It finds them through its own resolved path, so symlinks
# on PATH work.
mkdir "${tmp}/stage"
# tar fails when a named member is missing, so check its status, not just
# the result.
if ! tar -xzf "${tmp}/${asset}" -C "${tmp}/stage" --no-same-owner --strip-components=2 \
    "keycloak-${IL_VERSION}/bin/kcadm.sh" "keycloak-${IL_VERSION}/bin/client" \
    || [ ! -f "${tmp}/stage/kcadm.sh" ] || [ ! -d "${tmp}/stage/client" ]; then
    echo "cli-keycloak: ${asset} has no bin/kcadm.sh or bin/client/" >&2
    exit 1
fi
rm -f "${tmp}/${asset}"
chmod -R u=rwX,go=rX "${tmp}/stage"
chmod 0755 "${tmp}/stage/kcadm.sh"

if [ "$install_jre" = true ]; then
    il_apt_install default-jre-headless
fi

rm -rf "$lib_dir"
mkdir -p "$(dirname "$lib_dir")"
mv "${tmp}/stage" "$lib_dir"
ln -sfn "${lib_dir}/kcadm.sh" /usr/local/bin/kcadm.sh
ln -sfn "${lib_dir}/kcadm.sh" /usr/local/bin/kcadm

# Prints the running Java's major version (e.g. 21), or nothing.
java_major() {
    java -XshowSettings:properties -version 2>&1 \
        | awk -F'= ' '/^[[:space:]]*java\.specification\.version =/ { sub(/^1\./, "", $2); split($2, v, "."); print v[1]; exit }'
}

# kcadm.sh runs the first java on PATH, which may not be the JRE just
# installed, so the message names the one it found.
if java_bin="$(command -v java)"; then
    major="$(java_major)"
    if ! [[ "$major" =~ ^[0-9]+$ ]] || [ "$major" -lt "$min_java" ]; then
        if [ "$install_jre" = true ]; then
            echo "cli-keycloak: the first java on PATH (${java_bin}) is version '${major}', but kcadm needs ${min_java} or newer; default-jre-headless was installed, so check for an older java earlier on PATH" >&2
            exit 1
        fi
        echo "cli-keycloak: warning: java on PATH (${java_bin}) is version '${major}'; kcadm needs ${min_java} or newer" >&2
    fi
elif [ "$install_jre" = true ]; then
    echo "cli-keycloak: default-jre-headless installed no java on PATH" >&2
    exit 1
else
    echo "cli-keycloak: note: no java on PATH; kcadm needs Java ${min_java} or newer at run time (install_jre is false)"
fi

echo "cli-keycloak: installed kcadm.sh ${IL_VERSION} in ${lib_dir} (kcadm and kcadm.sh on PATH)"
