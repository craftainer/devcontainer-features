# shellcheck shell=bash
# Checks shared by the cli-valkey scenario scripts. The CLI copies this test
# folder into the test container's workspace, next to the scenario scripts
# and scenarios.json. Source it after dev-container-features-test-lib.

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

# Prints CLI_VALKEY_VERSION from the pins file <file>.
pins_version() {
    sed -nE 's/^[[:blank:]]*(export[[:blank:]]+)?CLI_VALKEY_VERSION=["'\'']?([^"'\''[:blank:]#]+).*/\2/p' "$1" | tail -n 1
}

_valkey_cli_is_local_bin() {
    [ "$(command -v valkey-cli)" = /usr/local/bin/valkey-cli ]
}

_valkey_cli_mode_owner() {
    [ "$(stat -c '%a %u' /usr/local/bin/valkey-cli)" = "755 0" ]
}

# valkey-cli --version prints e.g. "valkey-cli 9.1.3 (git:29173b67)".
_valkey_cli_reports() {
    local out
    out="$(valkey-cli --version)"
    echo "valkey-cli --version: ${out}"
    case "$out" in
        "valkey-cli $1" | "valkey-cli $1 "*) return 0 ;;
    esac
    return 1
}

_valkey_cli_help() {
    valkey-cli --help | grep -q '^Usage: valkey-cli '
}

# Only the client is installed: none of the tarball's other binaries, and
# no redis-cli alias.
_only_valkey_cli_installed() {
    local name
    for name in valkey-server valkey-sentinel valkey-benchmark valkey-check-aof valkey-check-rdb redis-cli; do
        if [ -e "/usr/local/bin/${name}" ] || command -v "$name" >/dev/null 2>&1; then
            echo "unexpected ${name} on PATH" >&2
            return 1
        fi
    done
}

_feature_declares_no_mounts() {
    ! grep -q '"mounts"' "$(dirname "$0")/.devcontainer/cli-valkey/devcontainer-feature.json"
}

# expect_installed <version>: valkey-cli is /usr/local/bin/valkey-cli,
# root-owned, mode 0755, reports <version> and prints its usage; nothing
# else from the tarball is installed and the feature declares no mounts.
expect_installed() {
    if [ -z "$1" ]; then
        echo "expect_installed: no expected version" >&2
        return 1
    fi
    check "valkey-cli resolves to /usr/local/bin/valkey-cli" _valkey_cli_is_local_bin
    check "valkey-cli is mode 0755, owned by root" _valkey_cli_mode_owner
    check "valkey-cli --version reports $1" _valkey_cli_reports "$1"
    check "valkey-cli --help prints its usage" _valkey_cli_help
    check "only valkey-cli is installed from the tarball" _only_valkey_cli_installed
    check "the feature declares no mounts" _feature_declares_no_mounts
}

# valkey_server_smoke <version> <sha_amd64> <sha_arm64>: downloads the same
# release tarball into a scratch directory (sha-checked with the feature's
# own install-lib.sh), starts its valkey-server on a unix socket with a
# password, and checks that the installed valkey-cli is refused without
# it and gets PONG with REDISCLI_AUTH or VALKEYCLI_AUTH, and that
# VALKEYCLI_AUTH wins over a wrong REDISCLI_AUTH (as NOTES.md says). The
# server is never installed; the directory is removed afterwards.
valkey_server_smoke() {
    local dir result=0
    dir="$(mktemp -d)" || return 1
    _valkey_server_smoke_in "$dir" "$@" || result=$?
    if [ -f "${dir}/server.pid" ]; then
        kill "$(cat "${dir}/server.pid")" 2>/dev/null || true
        wait "$(cat "${dir}/server.pid")" 2>/dev/null || true
    fi
    rm -rf "$dir"
    return "$result"
}

_valkey_server_smoke_in() {
    local dir="$1" version="$2" asset_arch sha lib sock out i
    case "$(uname -m)" in
        x86_64) asset_arch=x86_64 sha="$3" ;;
        *) asset_arch=arm64 sha="$4" ;;
    esac
    lib="$(cd "$(dirname "$0")" && pwd)/.devcontainer/cli-valkey/install-lib.sh"
    local tree="valkey-${version}-noble-${asset_arch}"
    bash -c '. "$1" && il_fetch_verified "$2" "$3" "$4"' _ "$lib" \
        "https://download.valkey.io/releases/${tree}.tar.gz" "$sha" "${dir}/${tree}.tar.gz" \
        || return 1
    tar -xzf "${dir}/${tree}.tar.gz" -C "$dir" --no-same-owner "${tree}/bin/valkey-server" || return 1
    rm -f "${dir}/${tree}.tar.gz"
    sock="${dir}/valkey.sock"
    "${dir}/${tree}/bin/valkey-server" --port 0 --unixsocket "$sock" \
        --requirepass smoke-secret --save '' --appendonly no --dir "$dir" \
        --logfile "${dir}/server.log" &
    echo "$!" >"${dir}/server.pid"
    for i in $(seq 1 50); do
        [ -S "$sock" ] && break
        sleep 0.2
    done
    if [ ! -S "$sock" ]; then
        echo "valkey-server did not open ${sock} (try ${i}):" >&2
        cat "${dir}/server.log" >&2 || true
        return 1
    fi
    out="$(env -u REDISCLI_AUTH -u VALKEYCLI_AUTH valkey-cli -s "$sock" ping 2>&1)" || true
    echo "no password: ${out}"
    case "$out" in
        *NOAUTH*) ;;
        *) echo "expected NOAUTH without a password" >&2 && return 1 ;;
    esac
    out="$(env -u VALKEYCLI_AUTH REDISCLI_AUTH=smoke-secret valkey-cli -s "$sock" ping 2>&1)"
    echo "REDISCLI_AUTH: ${out}"
    [ "$out" = PONG ] || return 1
    out="$(env -u REDISCLI_AUTH VALKEYCLI_AUTH=smoke-secret valkey-cli -s "$sock" ping 2>&1)"
    echo "VALKEYCLI_AUTH: ${out}"
    [ "$out" = PONG ] || return 1
    out="$(env VALKEYCLI_AUTH=smoke-secret REDISCLI_AUTH=wrong valkey-cli -s "$sock" ping 2>&1)"
    echo "VALKEYCLI_AUTH over a wrong REDISCLI_AUTH: ${out}"
    [ "$out" = PONG ] || return 1
}

_license_notice_ok() {
    [ "$(stat -c '%a %u' "$1")" = "644 0" ] && grep -qF "$2" "$1"
}

# expect_license_notice <file> <text>: <file> is a root-owned, mode 0644
# license notice that contains <text>.
expect_license_notice() {
    check "license notice $1 is mode 0644, owned by root, and has '$2'" _license_notice_ok "$1" "$2"
}
