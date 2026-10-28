# shellcheck shell=bash
# Checks shared by the cli-mosquitto scenario scripts. The CLI copies this
# test folder into the test container's workspace, next to the scenario
# scripts and scenarios.json. Source it after dev-container-features-test-lib.
#
# The pin differs per distro (repo.mosquitto.org on Debian, Ubuntu's own
# archive on Ubuntu), so every scenario's Dockerfile writes this distro's
# pin into a pins file, and the scripts read it back from there.

# The CLI copies the feature into the workspace's .devcontainer/ folder.
test_dir="$(cd "$(dirname "$0")" && pwd)"
feature_dir="${test_dir}/.devcontainer/cli-mosquitto"
install_sh="${feature_dir}/install.sh"
clean_path=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Prints CLI_MOSQUITTO_VERSION from the pins file <file>.
pins_version() {
    sed -nE 's/^[[:blank:]]*(export[[:blank:]]+)?CLI_MOSQUITTO_VERSION=["'\'']?([^"'\''[:blank:]#]+).*/\2/p' "$1" | tail -n 1
}

# Prints ID from /etc/os-release (debian or ubuntu), read in a subshell.
os_id() {
    # shellcheck source=/dev/null
    (. /etc/os-release && echo "${ID:-}")
}

as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

# Succeeds when dpkg has mosquitto-clients fully installed.
clients_installed() {
    [ "$(dpkg-query -W -f='${db:Status-Abbrev}' mosquitto-clients 2>/dev/null)" = "ii " ]
}

clients_absent() {
    ! clients_installed
}

purge_clients() {
    as_root apt-get purge -y -q mosquitto-clients >/dev/null
}

# _tool_reports <tool> <version>: "<tool> version <v> running on
# libmosquitto <v>." (the clients exit 1 after printing the version).
_tool_reports() {
    local out
    out="$("$1" --version 2>&1)" || true
    echo "$1 --version: ${out}"
    [ "$out" = "$1 version $2 running on libmosquitto $2." ]
}

# _pkg_version_is <pkg> <version>: dpkg has <pkg> installed at
# <version>-<revision>.
_pkg_version_is() {
    local status ver
    status="$(dpkg-query -W -f='${db:Status-Abbrev}' "$1" 2>/dev/null)" || return 1
    ver="$(dpkg-query -W -f='${Version}' "$1")"
    echo "$1: ${status% } ${ver}"
    [ "${status% }" = ii ] || return 1
    case "$ver" in
        "$2"-*) return 0 ;;
    esac
    return 1
}

# libmosquitto1 is at exactly mosquitto-clients' version (the clients
# Depend on libmosquitto1 (= their own version)).
_lib_matches_clients() {
    local lib clients
    lib="$(dpkg-query -W -f='${Version}' libmosquitto1)" || return 1
    clients="$(dpkg-query -W -f='${Version}' mosquitto-clients)" || return 1
    echo "libmosquitto1 ${lib}, mosquitto-clients ${clients}"
    [ -n "$lib" ] && [ "$lib" = "$clients" ]
}

# Only mosquitto-clients is marked manually installed; libmosquitto1 is
# automatic.
_only_clients_manual() {
    local manual
    manual="$(apt-mark showmanual | grep -E '^(mosquitto|libmosquitto)' || true)"
    echo "manually installed: ${manual}"
    [ "$manual" = mosquitto-clients ]
}

# Debian: repo.mosquitto.org's keyring and list are in place. Ubuntu: no
# repository was added, so nothing names repo.mosquitto.org.
_repo_state() {
    local codename
    # shellcheck source=/dev/null
    codename="$(. /etc/os-release && echo "${VERSION_CODENAME:-}")"
    case "$(os_id)" in
        debian)
            [ -s /etc/apt/keyrings/mosquitto.gpg ] || return 1
            grep -Fqx "deb [signed-by=/etc/apt/keyrings/mosquitto.gpg] https://repo.mosquitto.org/debian ${codename} main" \
                /etc/apt/sources.list.d/mosquitto.list
            ;;
        ubuntu)
            if [ -e /etc/apt/keyrings/mosquitto.gpg ] || [ -e /etc/apt/sources.list.d/mosquitto.list ]; then
                echo "a mosquitto keyring or list exists on Ubuntu" >&2
                return 1
            fi
            ! grep -rqs repo.mosquitto.org /etc/apt/sources.list /etc/apt/sources.list.d
            ;;
        *) return 1 ;;
    esac
}

# The apt lists are removed after the install: no Packages index is left.
_apt_lists_cleaned() {
    [ -z "$(find /var/lib/apt/lists -maxdepth 1 -name '*_Packages*' -print -quit)" ]
}

# mosquitto_pub against a port nothing listens on fails with "Connection
# refused" and exit 1. No broker is started.
_pub_connection_refused() {
    local out status=0
    out="$(mosquitto_pub -h 127.0.0.1 -p 1 -t t -m m 2>&1)" || status=$?
    echo "mosquitto_pub exit ${status}: ${out}"
    [ "$status" -eq 1 ] && [ "$out" = "Error: Connection refused" ]
}

_feature_declares_no_mounts_or_installs_after() {
    ! grep -Eq '"(mounts|installsAfter)"' "${feature_dir}/devcontainer-feature.json"
}

# expect_installed <version>: the three clients report <version> on
# libmosquitto <version>, dpkg has mosquitto-clients and libmosquitto1 at
# the same <version>-<revision>, only mosquitto-clients is manual, the
# repository state fits the distro, the apt lists are cleaned, and the
# feature declares no mounts or installsAfter.
expect_installed() {
    if [ -z "$1" ]; then
        echo "expect_installed: no expected version" >&2
        return 1
    fi
    check "mosquitto_pub reports $1" _tool_reports mosquitto_pub "$1"
    check "mosquitto_sub reports $1" _tool_reports mosquitto_sub "$1"
    check "mosquitto_rr reports $1" _tool_reports mosquitto_rr "$1"
    check "mosquitto-clients is installed at $1-<revision>" _pkg_version_is mosquitto-clients "$1"
    check "libmosquitto1 is at mosquitto-clients' version" _lib_matches_clients
    check "only mosquitto-clients is marked manually installed" _only_clients_manual
    check "the $(os_id) repository state is right (Debian: repo.mosquitto.org keyring and list; Ubuntu: none)" _repo_state
    check "the apt lists are cleaned" _apt_lists_cleaned
    check "mosquitto_pub reports Connection refused from an empty port" _pub_connection_refused
    check "the feature declares no mounts or installsAfter" _feature_declares_no_mounts_or_installs_after
}

# run_expect_failure <ERE> <command...>: succeeds when the command fails
# and its output matches <ERE>.
run_expect_failure() {
    local pattern="$1" out status=0
    shift
    out="$("$@" 2>&1)" || status=$?
    printf '%s\n' "$out" | tail -n 5
    if [ "$status" -eq 0 ]; then
        echo "succeeded; expected a failure" >&2
        return 1
    fi
    if ! printf '%s\n' "$out" | grep -Eq -- "$pattern"; then
        echo "output doesn't match: ${pattern}" >&2
        return 1
    fi
}

# run_install [VAR=value...]: runs install.sh as root in a clean
# environment with only the given variables.
run_install() {
    as_root env -i PATH="$clean_path" "$@" bash "$install_sh"
}
