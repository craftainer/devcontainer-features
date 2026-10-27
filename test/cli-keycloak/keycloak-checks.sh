# shellcheck shell=bash
# Checks shared by the cli-keycloak scenario scripts. The CLI copies this
# test folder into the test container's workspace, next to the scenario
# scripts and scenarios.json, and the feature itself into its
# .devcontainer/ folder. Source it after dev-container-features-test-lib.

test_dir="$(cd "$(dirname "$0")" && pwd)"
feature_dir="${test_dir}/.devcontainer/cli-keycloak"
lib_dir=/usr/local/lib/keycloak-cli

# Prints the "version" option of scenario <name> in scenarios.json.
scenario_version() {
    awk -v name="\"$1\":" '
        $1 == name { inside = 1; next }
        inside && /"version":/ { gsub(/[",]/, "", $2); print $2; exit }
    ' "${test_dir}/scenarios.json"
}

# Prints CLI_KEYCLOAK_<KEY> from the pins file <file>.
pins_value() {
    sed -nE "s/^[[:blank:]]*(export[[:blank:]]+)?CLI_KEYCLOAK_$2=[\"']?([^\"'[:blank:]#]+).*/\\2/p" "$1" | tail -n 1
}

_feature_declares_no_mounts() {
    ! grep -q '"mounts"' "${feature_dir}/devcontainer-feature.json"
}

_is_link_to_lib() {
    [ "$(command -v "$1")" = "/usr/local/bin/$1" ] \
        && [ -L "/usr/local/bin/$1" ] \
        && [ "$(readlink -f "/usr/local/bin/$1")" = "${lib_dir}/kcadm.sh" ]
}

_lib_has_version() {
    [ -x "${lib_dir}/kcadm.sh" ] \
        && [ -f "${lib_dir}/client/keycloak-admin-cli-$1.jar" ] \
        && [ -d "${lib_dir}/client/lib" ] \
        && [ "$(stat -c '%u' "${lib_dir}/kcadm.sh")" = 0 ]
}

# Only kcadm.sh and client/ come out of the tarball.
_lib_has_only_kcadm() {
    [ "$(find "$lib_dir" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort | tr '\n' ' ')" = "client kcadm.sh " ]
}

_runs_help() {
    local out status=0
    out="$("$1" --help 2>&1)" || status=$?
    printf '%s\n' "$out" | head -n 5
    [ "$status" -eq 0 ] && printf '%s\n' "$out" | grep -q 'Usage: kcadm.sh'
}

_java_at_least_21() {
    local major
    major="$(java -XshowSettings:properties -version 2>&1 \
        | awk -F'= ' '/^[[:space:]]*java\.specification\.version =/ { split($2, v, "."); print v[1]; exit }')"
    echo "java major version: ${major}"
    [[ "$major" =~ ^[0-9]+$ ]] && [ "$major" -ge 21 ]
}

_no_java() {
    ! command -v java >/dev/null 2>&1 && ! dpkg -s default-jre-headless >/dev/null 2>&1
}

# expect_official <version> [jre]: kcadm.sh <version> is installed in
# /usr/local/lib/keycloak-cli with kcadm and kcadm.sh on PATH. With "jre"
# (the default), Java 21+ is installed and both names run --help; with
# "no-jre", there is no Java and nothing is run.
expect_official() {
    if [ -z "$1" ]; then
        echo "expect_official: no expected version" >&2
        return 1
    fi
    check "kcadm.sh is a link on PATH to ${lib_dir}/kcadm.sh" _is_link_to_lib kcadm.sh
    check "kcadm is a link on PATH to ${lib_dir}/kcadm.sh" _is_link_to_lib kcadm
    check "${lib_dir} holds the $1 admin CLI jar, root-owned" _lib_has_version "$1"
    check "${lib_dir} holds only kcadm.sh and client/" _lib_has_only_kcadm
    if [ "${2:-jre}" = jre ]; then
        check "Java 21 or newer is installed" _java_at_least_21
        check "kcadm.sh --help runs under the JRE" _runs_help kcadm.sh
        check "kcadm --help runs under the JRE" _runs_help kcadm
    else
        check "no java on PATH and no default-jre-headless" _no_java
    fi
    check "the feature declares no mounts" _feature_declares_no_mounts
}

_is_wrapper() {
    [ "$(command -v kcadm)" = /usr/local/bin/kcadm ] \
        && [ -f /usr/local/bin/kcadm ] && [ ! -L /usr/local/bin/kcadm ] \
        && [ "$(stat -c '%a %u' /usr/local/bin/kcadm)" = "755 0" ] \
        && cmp -s /usr/local/bin/kcadm "${feature_dir}/kcadm-rest.sh"
}

_wrapper_usage() {
    local out status=0
    out="$(kcadm GET 2>&1)" || status=$?
    printf '%s\n' "$out"
    [ "$status" -eq 1 ] && printf '%s\n' "$out" | grep -qx 'Usage: kcadm METHOD PATH \[JSON_BODY\]'
}

_has_curl_python() {
    command -v curl >/dev/null && command -v python3 >/dev/null
}

_no_official_install() {
    [ ! -e "$lib_dir" ] && [ ! -e /usr/local/bin/kcadm.sh ]
}

# _with_mock <command...>: runs <command> with a mock Keycloak
# (mock_keycloak.py, admin user "admin", password "s3cret") listening on
# 127.0.0.1 and KEYCLOAK_URL pointing at it, then stops the mock.
_with_mock() {
    local dir pid status=0 _
    dir="$(mktemp -d)" || return 1
    python3 -I "${test_dir}/mock_keycloak.py" "${dir}/port" admin s3cret &
    pid=$!
    for _ in $(seq 1 50); do
        [ -s "${dir}/port" ] && break
        sleep 0.1
    done
    if [ ! -s "${dir}/port" ]; then
        echo "the mock Keycloak did not start" >&2
        kill "$pid" 2>/dev/null || true
        rm -rf "$dir"
        return 1
    fi
    KEYCLOAK_URL="http://127.0.0.1:$(cat "${dir}/port")" "$@" || status=$?
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    rm -rf "$dir"
    return "$status"
}

_wrapper_round_trip() {
    local out
    out="$(KEYCLOAK_ADMIN=admin KEYCLOAK_ADMIN_PASSWORD=s3cret \
        kcadm POST /admin/realms/demo/users '{"username": "alice"}')" || return 1
    printf '%s\n' "$out"
    printf '%s\n' "$out" | grep -q '"method": "POST"' \
        && printf '%s\n' "$out" | grep -q '"path": "/admin/realms/demo/users"' \
        && printf '%s\n' "$out" | grep -q '"content_type": "application/json"' \
        && printf '%s\n' "$out" | grep -q '"username": "alice"'
}

_wrapper_bad_login_fails() {
    ! KEYCLOAK_ADMIN=admin KEYCLOAK_ADMIN_PASSWORD=wrong \
        kcadm GET /admin/realms >/dev/null 2>&1
}

# expect_rest: the rest wrapper is /usr/local/bin/kcadm, byte for byte;
# it prints its usage, talks to a mock Keycloak, and fails a bad login;
# no tarball or JRE was installed.
expect_rest() {
    check "kcadm is the rest wrapper, root-owned, mode 0755" _is_wrapper
    check "kcadm with too few arguments prints its usage and exits 1" _wrapper_usage
    check "curl and python3 are installed" _has_curl_python
    check "kcadm gets a token and sends the request with it" _with_mock _wrapper_round_trip
    check "kcadm fails on a bad login" _with_mock _wrapper_bad_login_fails
    check "no Keycloak tarball was installed" _no_official_install
    check "no Java is installed" _no_java
    check "the feature declares no mounts" _feature_declares_no_mounts
}
