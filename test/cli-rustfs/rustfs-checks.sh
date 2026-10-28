# shellcheck shell=bash
# Checks shared by the cli-rustfs scenario scripts. The CLI copies this test
# folder into the test container's workspace, next to the scenario scripts
# and scenarios.json. Source it after dev-container-features-test-lib.

# Prints the "version" option of scenario <name> in scenarios.json. The
# search stops at the scenario's closing brace, so a scenario without a
# version never prints the next scenario's.
scenario_version() {
    awk -v name="\"$1\":" '
        $1 == name { inside = 1; next }
        inside && /^  },?[[:space:]]*$/ { exit }
        inside && /"version":/ { gsub(/[",]/, "", $2); print $2; exit }
    ' "$(dirname "$0")/scenarios.json"
}

# Prints CLI_RUSTFS_VERSION from the pins file <file>.
pins_version() {
    sed -nE 's/^[[:blank:]]*(export[[:blank:]]+)?CLI_RUSTFS_VERSION=["'\'']?([^"'\''[:blank:]#]+).*/\2/p' "$1" | tail -n 1
}

_rc_is_usr_bin() {
    [ "$(command -v rc)" = /usr/bin/rc ]
}

_rc_package_is() {
    local got
    got="$(dpkg-query -W -f='${Version}' rustfs-cli)"
    echo "rustfs-cli package: ${got}"
    [ "$got" = "$1" ]
}

_rc_reports() {
    local out
    out="$(rc --version)"
    echo "rc --version: ${out}"
    case "$out" in
        *" $1" | *" $1 "* | *" v$1" | *" v$1 "*) return 0 ;;
    esac
    return 1
}

# rc alias set with keys verifies them with a ListBuckets call before
# saving, so offline only an --anonymous alias can be set. This sets one
# against an endpoint nothing listens on, in a throwaway RC_CONFIG_DIR, and
# checks that rc writes and lists it.
_rc_alias_set_offline() {
    local dir result=0
    dir="$(mktemp -d)" || return 1
    RC_CONFIG_DIR="$dir" rc alias set dummy http://127.0.0.1:9 --anonymous || result=1
    if [ "$result" -eq 0 ]; then
        RC_CONFIG_DIR="$dir" rc alias list --json | grep -q '"dummy"' || result=1
    fi
    if [ "$result" -eq 0 ]; then
        grep -q 'http://127.0.0.1:9' "${dir}/config.toml" || result=1
    fi
    rm -rf "$dir"
    return "$result"
}

# The behaviour NOTES.md documents: an alias with keys for an unreachable
# endpoint is refused and not saved.
_rc_alias_set_needs_endpoint() {
    local dir result=0
    dir="$(mktemp -d)" || return 1
    if RC_CONFIG_DIR="$dir" rc alias set dummy http://127.0.0.1:9 AKEXAMPLE SKEXAMPLE; then
        echo "rc alias set succeeded against a closed port" >&2
        result=1
    elif RC_CONFIG_DIR="$dir" rc alias list --json | grep -q '"dummy"'; then
        echo "rc alias set saved the alias after failing" >&2
        result=1
    fi
    rm -rf "$dir"
    return "$result"
}

_apt_lists_removed() {
    [ -z "$(find /var/lib/apt/lists -mindepth 1 -maxdepth 1 -name '*_Packages*' -print -quit 2>/dev/null)" ]
}

_feature_declares_no_mounts() {
    ! grep -q '"mounts"' "$(dirname "$0")/.devcontainer/cli-rustfs/devcontainer-feature.json"
}

# expect_installed <version>: rc resolves to /usr/bin/rc from the
# rustfs-cli package at <version>, reports it, can set an anonymous alias
# offline and refuses a keyed one for an unreachable endpoint; the apt
# lists are gone and the feature declares no mounts.
expect_installed() {
    if [ -z "$1" ]; then
        echo "expect_installed: no expected version" >&2
        return 1
    fi
    check "rc resolves to /usr/bin/rc" _rc_is_usr_bin
    check "the rustfs-cli package is $1" _rc_package_is "$1"
    check "rc --version reports $1" _rc_reports "$1"
    check "rc alias set --anonymous works offline" _rc_alias_set_offline
    check "rc alias set with keys needs a reachable endpoint" _rc_alias_set_needs_endpoint
    check "the apt lists were removed" _apt_lists_removed
    check "the feature declares no mounts" _feature_declares_no_mounts
}
