# shellcheck shell=bash
# Shared checks for the ssl-ca scenarios (and test/_global), sourced after
# dev-container-features-test-lib.
#
# All CA material is generated at test time (or in a scenario Dockerfile)
# with openssl; no private key is committed. The one static certificate,
# STATIC_CA_PEM below, is a CA whose private key was deleted right after
# it was made, so nothing can be signed with it: it can only show that an
# inline certificate lands in the trust store. TLS handshakes use a CA
# made at test time.

BUNDLE=/etc/ssl/certs/ca-certificates.crt

# The static test CA: CN "ssl-ca feature static test CA (no private key
# exists)", valid until 2126. The same PEM is in scenarios.json
# (option_certs, rejects_bad_inputs) and env_certs/Dockerfile.
export STATIC_CA_SHA256=2228d064e436d9e3f686c92ec5358fae7a95605bad36ce479f309ae0915c98e4

as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

# fingerprint <pem>: the sha256 fingerprint, 64 lower-case hex digits.
fingerprint() {
    local fp
    fp="$(openssl x509 -in "$1" -noout -fingerprint -sha256)" || return 1
    fp="${fp#*=}"
    fp="${fp//:/}"
    printf '%s' "${fp,,}"
}

# bundle_has <sha256 fingerprint>: succeeds when a certificate with that
# fingerprint is in the system bundle.
bundle_has() {
    local want="$1" dir pem result=1
    dir="$(mktemp -d)" || return 1
    awk -v d="$dir" '/^-----BEGIN CERTIFICATE-----/ { n++; f = sprintf("%s/%04d.pem", d, n) } f { print > f } /^-----END CERTIFICATE-----/ { close(f); f = "" }' "$BUNDLE"
    for pem in "$dir"/*.pem; do
        if [ "$(fingerprint "$pem")" = "$want" ]; then
            result=0
            break
        fi
    done
    rm -rf "$dir"
    if [ "$result" -ne 0 ]; then
        echo "no certificate with sha256 fingerprint ${want} in ${BUNDLE}" >&2
    fi
    return "$result"
}

# bundle_has_pem <pem>: bundle_has for the certificate in <pem>.
bundle_has_pem() {
    bundle_has "$(fingerprint "$1")"
}

# container_env_ok: every variable ssl-ca sets in containerEnv has its
# value.
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

# make_ca <dir>: a throwaway CA in <dir>/ca.pem and <dir>/ca.key.
make_ca() {
    mkdir -p "$1"
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
        -keyout "$1/ca.key" -out "$1/ca.pem" -days 2 \
        -subj "/CN=ssl-ca throwaway test CA $(basename "$1") $$" \
        -addext basicConstraints=critical,CA:TRUE \
        -addext keyUsage=critical,keyCertSign,cRLSign 2>/dev/null
}

# _make_leaf <ca dir> <out dir>: a localhost server certificate signed by
# that CA, in <out dir>/leaf.pem and <out dir>/leaf.key (the CA dir may be
# read-only).
_make_leaf() {
    local d="$1" o="$2"
    openssl req -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
        -keyout "$o/leaf.key" -out "$o/leaf.csr" -subj /CN=localhost 2>/dev/null || return 1
    printf 'subjectAltName=DNS:localhost,IP:127.0.0.1\nbasicConstraints=CA:FALSE\nextendedKeyUsage=serverAuth\n' >"$o/leaf.ext"
    openssl x509 -req -in "$o/leaf.csr" -CA "$d/ca.pem" -CAkey "$d/ca.key" \
        -CAcreateserial -CAserial "$o/ca.srl" -days 1 -extfile "$o/leaf.ext" -out "$o/leaf.pem" 2>/dev/null
}

_ensure_curl() {
    command -v curl >/dev/null 2>&1 && return 0
    as_root env DEBIAN_FRONTEND=noninteractive apt-get update >/dev/null
    as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends curl >/dev/null
}

# _https_get <ca dir>: serves https://localhost:<port>/ with a leaf signed
# by that CA (openssl s_server) and fetches it with curl, without -k and
# without --cacert, so curl uses CURL_CA_BUNDLE (containerEnv) or its
# default store. Returns curl's status.
_https_get() {
    local d="$1" o port pid status=0 i
    o="$(mktemp -d)" || return 1
    _make_leaf "$d" "$o" || return 1
    _ensure_curl || return 1
    port=$((20000 + RANDOM % 20000))
    openssl s_server -quiet -www -accept "$port" -cert "$o/leaf.pem" -key "$o/leaf.key" \
        </dev/null >/dev/null 2>&1 &
    pid=$!
    for i in $(seq 50); do
        if (exec 3<>"/dev/tcp/127.0.0.1/${port}") 2>/dev/null; then
            break
        fi
        [ "$i" -lt 50 ] || {
            echo "openssl s_server didn't listen on ${port}" >&2
            kill "$pid"
            return 1
        }
        sleep 0.1
    done
    curl -sS -o /dev/null --max-time 10 "https://localhost:${port}/" || status=$?
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    rm -rf "$o"
    return "$status"
}

# tls_trusted <ca dir>: curl completes a TLS handshake with a server whose
# certificate that CA signed.
tls_trusted() {
    _https_get "$1"
}

# tls_untrusted <ca dir>: the same handshake fails (curl exit 60, an
# unverified certificate), because the CA isn't installed.
tls_untrusted() {
    local status=0
    _https_get "$1" 2>/dev/null || status=$?
    if [ "$status" -ne 60 ]; then
        echo "curl exit ${status}, expected 60 (peer certificate cannot be authenticated)" >&2
        return 1
    fi
}

# ssl_ca_install_sh: the feature's install.sh as copied by the CLI into
# the test workspace.
ssl_ca_install_sh() {
    local d
    d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    printf '%s/.devcontainer/ssl-ca/install.sh' "$d"
}

# rerun_install [VAR=value...]: runs install.sh again as root in a clean
# environment with only the given variables (the way the CLI passes
# options), printing its output; returns its status.
rerun_install() {
    as_root env -i PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
        "$@" bash "$(ssl_ca_install_sh)" 2>&1
}

# escape_newlines <file>: prints the file on one line, with \n escapes.
escape_newlines() {
    awk '{ printf "%s\\n", $0 }' "$1"
}
