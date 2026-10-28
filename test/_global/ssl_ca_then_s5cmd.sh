#!/usr/bin/env bash
# ssl-ca, then cli-s5cmd (overrideFeatureInstallOrder puts ssl-ca first).
# The throwaway CA from the pins file must be in the system bundle, the CA
# variables must be set, curl must complete a TLS handshake with a server
# that CA signed, and s5cmd (Go, which reads SSL_CERT_FILE) must trust it
# too, while a CA that isn't installed is still rejected.
#
# The CLI copies only test/_global into this workspace, so the few helpers
# below are a trimmed copy of test/ssl-ca/ssl-ca-checks.sh.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib

BUNDLE=/etc/ssl/certs/ca-certificates.crt
ca=/opt/ssl-ca-test/global

as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

ca_in_bundle() {
    local body
    body="$(openssl x509 -in "${ca}/ca.pem" | tr -d ' \n\r')"
    [[ "$(tr -d ' \n\r' <"$BUNDLE")" == *"$body"* ]]
}

container_env_ok() {
    local name want status=0
    for name in SSL_CERT_FILE REQUESTS_CA_BUNDLE CURL_CA_BUNDLE PIP_CERT NODE_EXTRA_CA_CERTS \
        AWS_CA_BUNDLE GIT_SSL_CAINFO CARGO_HTTP_CAINFO DENO_CERT SSL_CERT_DIR NODE_USE_SYSTEM_CA UV_NATIVE_TLS; do
        case "$name" in
            SSL_CERT_DIR) want=/etc/ssl/certs ;;
            NODE_USE_SYSTEM_CA | UV_NATIVE_TLS) want=1 ;;
            *) want="$BUNDLE" ;;
        esac
        if [ "${!name:-}" != "$want" ]; then
            echo "${name} is '${!name:-}', expected '${want}'" >&2
            status=1
        fi
    done
    return "$status"
}

# make_ca <dir>: a throwaway CA that isn't installed.
make_ca() {
    mkdir -p "$1"
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
        -keyout "$1/ca.key" -out "$1/ca.pem" -days 2 -subj "/CN=ssl-ca untrusted test CA" \
        -addext basicConstraints=critical,CA:TRUE -addext keyUsage=critical,keyCertSign,cRLSign 2>/dev/null
}

# start_server <ca dir>: serves https://localhost:$port/ with a leaf that
# CA signed; sets port and server_pid.
start_server() {
    local d="$1" leaf
    leaf="$(mktemp -d)"
    openssl req -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
        -keyout "${leaf}/leaf.key" -out "${leaf}/leaf.csr" -subj /CN=localhost 2>/dev/null || return 1
    printf 'subjectAltName=DNS:localhost,IP:127.0.0.1\nbasicConstraints=CA:FALSE\nextendedKeyUsage=serverAuth\n' >"${leaf}/leaf.ext"
    openssl x509 -req -in "${leaf}/leaf.csr" -CA "${d}/ca.pem" -CAkey "${d}/ca.key" \
        -CAcreateserial -CAserial "${leaf}/ca.srl" -days 1 -extfile "${leaf}/leaf.ext" \
        -out "${leaf}/leaf.pem" 2>/dev/null || return 1
    port=$((20000 + RANDOM % 20000))
    openssl s_server -quiet -www -accept "$port" -cert "${leaf}/leaf.pem" -key "${leaf}/leaf.key" \
        </dev/null >/dev/null 2>&1 &
    server_pid=$!
    for _ in $(seq 50); do
        (exec 3<>"/dev/tcp/127.0.0.1/${port}") 2>/dev/null && return 0
        sleep 0.1
    done
    echo "openssl s_server didn't listen on ${port}" >&2
    return 1
}

stop_server() {
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
}

ensure_curl() {
    command -v curl >/dev/null 2>&1 && return 0
    as_root env DEBIAN_FRONTEND=noninteractive apt-get update >/dev/null
    as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends curl >/dev/null
}

# curl_status <ca dir>: prints curl's exit status for a GET of a server
# that CA signed (no -k, no --cacert).
curl_status() {
    local status=0
    start_server "$1" || return 1
    curl -sS -o /dev/null --max-time 10 "https://localhost:${port}/" 2>/dev/null || status=$?
    stop_server
    echo "$status"
}

curl_trusts() { [ "$(curl_status "$1")" = 0 ]; }
curl_rejects() { [ "$(curl_status "$1")" = 60 ]; }

# s5cmd_ls <ca dir>: runs s5cmd ls against a server that CA signed,
# leaving its output in s5cmd_out and its exit status in s5cmd_status.
# openssl s_server answers any GET with an HTML status page, which s5cmd
# reads as an empty listing, so a trusted server gives exit 0.
s5cmd_ls() {
    s5cmd_status=0
    start_server "$1" || return 1
    # A fixed region, so s5cmd sends the request itself instead of first
    # looking the bucket's region up.
    s5cmd_out="$(AWS_REGION=us-east-1 timeout 60 s5cmd --retry-count 0 --no-sign-request \
        --endpoint-url "https://localhost:${port}" ls s3://test-bucket/ 2>&1)" || s5cmd_status=$?
    stop_server
    printf 's5cmd exit %s: %s\n' "$s5cmd_status" "$s5cmd_out"
}

s5cmd_trusts() {
    s5cmd_ls "$1" || return 1
    [ "$s5cmd_status" -eq 0 ] && ! grep -qiE 'x509|certificate' <<<"$s5cmd_out"
}

s5cmd_rejects() {
    s5cmd_ls "$1" || return 1
    [ "$s5cmd_status" -ne 0 ] && grep -qiE 'x509: certificate signed by unknown authority' <<<"$s5cmd_out"
}

ensure_curl
other="$(mktemp -d)/other"
make_ca "$other"

check "the CA from ssl-ca is in the system bundle" ca_in_bundle
check "ssl-ca's containerEnv points the CA variables at the system bundle" container_env_ok
check "cli-s5cmd is installed" s5cmd version
check "curl completes a TLS handshake with a server the CA signed, without -k" curl_trusts "$ca"
check "curl rejects a server signed by a CA that isn't installed" curl_rejects "$other"
check "s5cmd trusts a server the CA signed (no certificate error)" s5cmd_trusts "$ca"
check "s5cmd rejects a server signed by a CA that isn't installed" s5cmd_rejects "$other"

reportResults
