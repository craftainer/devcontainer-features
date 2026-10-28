# shellcheck shell=bash
# Checks shared by the cli-postgres-client scenario scripts. The CLI copies
# this test folder into the test container's workspace, next to the
# scenario scripts and scenarios.json. Source it after
# dev-container-features-test-lib.

# Prints option <key> of scenario <name> in scenarios.json. The search
# stops at the scenario's closing brace, so a scenario without the key
# never prints the next scenario's.
scenario_option() {
    awk -v name="\"$1\":" -v key="\"$2\":" '
        $1 == name { inside = 1; next }
        inside && /^  },?[[:space:]]*$/ { exit }
        inside && $1 == key { gsub(/[",]/, "", $2); print $2; exit }
    ' "$(dirname "$0")/scenarios.json"
}

# Prints the "version" option of scenario <name> in scenarios.json.
scenario_version() {
    scenario_option "$1" version
}

# Prints CLI_POSTGRES_CLIENT_VERSION from the pins file <file>.
pins_version() {
    sed -nE 's/^[[:blank:]]*(export[[:blank:]]+)?CLI_POSTGRES_CLIENT_VERSION=["'\'']?([^"'\''[:blank:]#]+).*/\2/p' "$1" | tail -n 1
}

as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

# Prints the client package for upstream version <v>: postgresql-client-18
# for 18.6.
client_pkg() {
    printf 'postgresql-client-%s' "${1%%.*}"
}

# _tool_reports <tool> <version>: <tool> --version prints e.g.
# "psql (PostgreSQL) 18.6 (Debian 18.6-1.pgdg13+2)".
_tool_reports() {
    local out
    out="$("$1" --version)"
    echo "$1 --version: ${out}"
    case "$out" in
        "$1 (PostgreSQL) $2" | "$1 (PostgreSQL) $2 "*) return 0 ;;
    esac
    return 1
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

# Only the pinned client is marked manually installed; its dependencies
# (libpq5, postgresql-client-common) are automatic.
_only_client_manual() {
    local manual
    manual="$(apt-mark showmanual | grep -E '^(postgresql|libpq)' || true)"
    echo "manually installed: ${manual}"
    [ "$manual" = "$1" ]
}

_pgdg_keyrings_and_lists() {
    local name
    for name in pgdg pgdg-archive; do
        [ -s "/etc/apt/keyrings/${name}.gpg" ] || return 1
        grep -q "^deb \[signed-by=/etc/apt/keyrings/${name}.gpg\] https://apt" \
            "/etc/apt/sources.list.d/${name}.list" || return 1
    done
}

# The apt lists are removed after the install: no Packages index is left.
_apt_lists_cleaned() {
    [ -z "$(find /var/lib/apt/lists -maxdepth 1 -name '*_Packages*' -print -quit)" ]
}

# pg_isready against a port nothing listens on reports "no response" (exit
# 2). No server is started.
_pg_isready_no_response() {
    local status=0
    pg_isready -h 127.0.0.1 -p 1 -t 3 || status=$?
    echo "pg_isready exit ${status}"
    [ "$status" -eq 2 ]
}

_feature_declares_no_mounts_or_installs_after() {
    ! grep -Eq '"(mounts|installsAfter)"' \
        "$(dirname "$0")/.devcontainer/cli-postgres-client/devcontainer-feature.json"
}

# expect_installed <version>: psql, pg_dump and pg_restore report
# <version>, dpkg has postgresql-client-<major> at <version>-<revision>,
# PGDG's keyrings and lists are in place, the apt lists are cleaned, and
# the feature declares no mounts or installsAfter.
expect_installed() {
    if [ -z "$1" ]; then
        echo "expect_installed: no expected version" >&2
        return 1
    fi
    local pkg
    pkg="$(client_pkg "$1")"
    check "psql reports $1" _tool_reports psql "$1"
    check "pg_dump reports $1" _tool_reports pg_dump "$1"
    check "pg_restore reports $1" _tool_reports pg_restore "$1"
    check "${pkg} is installed at $1-<revision>" _pkg_version_is "$pkg" "$1"
    check "only ${pkg} is marked manually installed" _only_client_manual "$pkg"
    check "the pgdg and pgdg-archive keyrings and lists are in place" _pgdg_keyrings_and_lists
    check "the apt lists are cleaned" _apt_lists_cleaned
    check "pg_isready reports no response from an empty port" _pg_isready_no_response
    check "the feature declares no mounts or installsAfter" _feature_declares_no_mounts_or_installs_after
}
