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

# The mock's admin password: every character that needs URL-encoding in a
# form body, plus a space.
mock_password='p+&%@ x'

# _with_mock <command...>: runs <command> with a mock Keycloak
# (mock_keycloak.py, admin user "admin", password $mock_password) on
# 127.0.0.1, KEYCLOAK_URL pointing at it and KEYCLOAK_ADMIN and
# KEYCLOAK_ADMIN_PASSWORD set to match, then stops the mock.
_with_mock() {
    local dir pid status=0 _
    dir="$(mktemp -d)" || return 1
    python3 -I "${test_dir}/mock_keycloak.py" "${dir}/port" admin "$mock_password" &
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
    KEYCLOAK_URL="http://127.0.0.1:$(cat "${dir}/port")" KEYCLOAK_ADMIN=admin \
        KEYCLOAK_ADMIN_PASSWORD="$mock_password" "$@" || status=$?
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    rm -rf "$dir"
    return "$status"
}

# run_kcadm <args...>: runs kcadm and sets kc_out, kc_err and kc_status,
# printing all three for the log.
run_kcadm() {
    local errf
    errf="$(mktemp)" || return 1
    kc_status=0
    kc_out="$(kcadm "$@" 2>"$errf")" || kc_status=$?
    kc_err="$(cat "$errf")"
    rm -f "$errf"
    printf 'exit %s\n--- stdout\n%s\n--- stderr\n%s\n' "$kc_status" "$kc_out" "$kc_err"
}

_has() { # <haystack> <fixed string>
    printf '%s\n' "$1" | grep -Fq -- "$2"
}

# A password with + & % @ and a space logs in (it is URL-encoded), and the
# request carries the token and the JSON body.
_wrapper_round_trip() {
    run_kcadm POST /admin/realms/demo/users '{"username": "alice"}'
    [ "$kc_status" -eq 0 ] \
        && _has "$kc_out" '"method": "POST"' \
        && _has "$kc_out" '"path": "/admin/realms/demo/users"' \
        && _has "$kc_out" '"content_type": "application/json"' \
        && _has "$kc_out" '"username": "alice"'
}

# A body starting with @ is sent as it is, never read as a file.
_wrapper_body_literal() {
    run_kcadm POST /admin/realms/demo/users '@/etc/hostname'
    [ "$kc_status" -eq 0 ] && _has "$kc_out" '"raw_body": "@/etc/hostname"'
}

_wrapper_404() {
    run_kcadm GET /status/404
    [ "$kc_status" -ne 0 ] && [ -z "$kc_out" ] \
        && _has "$kc_err" 'kcadm: GET /status/404: HTTP 404' \
        && _has "$kc_err" '"error": "not found"'
}

_wrapper_500_raw() {
    run_kcadm GET /status/500
    [ "$kc_status" -ne 0 ] && [ -z "$kc_out" ] \
        && _has "$kc_err" 'kcadm: GET /status/500: HTTP 500' \
        && _has "$kc_err" 'Internal Server Error: boom'
}

_wrapper_text_raw() {
    run_kcadm GET /text
    [ "$kc_status" -eq 0 ] && [ "$kc_out" = 'plain text reply' ]
}

_wrapper_bad_login() {
    KEYCLOAK_ADMIN_PASSWORD=wrong run_kcadm GET /admin/realms
    [ "$kc_status" -ne 0 ] && [ -z "$kc_out" ] \
        && _has "$kc_err" 'kcadm: login failed: HTTP 401' \
        && _has "$kc_err" '"error": "invalid_grant"' \
        && ! _has "$kc_err" 'Traceback'
}

# Each required variable, unset, is named, with no "unbound variable".
_wrapper_names_unset() {
    local var
    for var in KEYCLOAK_URL KEYCLOAK_ADMIN KEYCLOAK_ADMIN_PASSWORD; do
        env KEYCLOAK_URL=http://127.0.0.1:9 KEYCLOAK_ADMIN=admin KEYCLOAK_ADMIN_PASSWORD=x \
            env -u "$var" kcadm GET /admin/realms >/dev/null 2>"${test_tmp}/err" \
            && return 1
        cat "${test_tmp}/err"
        grep -Fq "kcadm: set ${var} " "${test_tmp}/err" || return 1
        ! grep -q 'unbound variable' "${test_tmp}/err" || return 1
    done
}

# Neither the password nor the token is in curl's arguments (what ps
# shows): a curl shim first on PATH logs every argument, then runs curl.
_wrapper_secrets_not_in_argv() {
    local shim="${test_tmp}/shim" real
    real="$(command -v curl)"
    mkdir -p "$shim"
    printf '#!/bin/sh\nprintf "%%s\\n" "$@" >>"%s"\nexec "%s" "$@"\n' "${test_tmp}/argv" "$real" >"${shim}/curl"
    chmod 0755 "${shim}/curl"
    : >"${test_tmp}/argv"
    PATH="${shim}:${PATH}" run_kcadm POST /admin/realms/demo/users '{"username": "alice"}'
    [ "$kc_status" -eq 0 ] \
        && [ "$(grep -c . "${test_tmp}/argv")" -gt 0 ] \
        && ! grep -Fq -- "$mock_password" "${test_tmp}/argv" \
        && ! grep -Fq -- 'mock-token-123' "${test_tmp}/argv" \
        && ! grep -Fq -- 'alice' "${test_tmp}/argv"
}

# expect_rest: the rest wrapper is /usr/local/bin/kcadm (the feature's
# kcadm-rest.sh); it prints its usage, names unset variables, and behaves
# against a mock Keycloak; no tarball or JRE was installed.
expect_rest() {
    test_tmp="$(mktemp -d)"
    check "kcadm is the rest wrapper, root-owned, mode 0755" _is_wrapper
    check "kcadm with too few arguments prints its usage and exits 1" _wrapper_usage
    check "kcadm names an unset KEYCLOAK_* variable" _wrapper_names_unset
    check "curl and python3 are installed" _has_curl_python
    check "a password with + & % @ and a space logs in; the request is sent" _with_mock _wrapper_round_trip
    check "a body starting with @ is sent literally" _with_mock _wrapper_body_literal
    check "a 404 exits non-zero with the body on stderr" _with_mock _wrapper_404
    check "a non-JSON 500 prints the raw body on stderr and exits non-zero" _with_mock _wrapper_500_raw
    check "a non-JSON 200 is printed as it is" _with_mock _wrapper_text_raw
    check "a bad login says so, without a traceback" _with_mock _wrapper_bad_login
    check "the password, token and body are not in curl's arguments" _with_mock _wrapper_secrets_not_in_argv
    check "no Keycloak tarball was installed" _no_official_install
    check "no Java is installed" _no_java
    check "the feature declares no mounts" _feature_declares_no_mounts
    rm -rf "$test_tmp"
}
