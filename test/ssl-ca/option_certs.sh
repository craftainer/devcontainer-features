#!/usr/bin/env bash
# The certs option, with literal newlines: scenarios.json passes the static
# test CA (no private key exists). A TLS handshake needs a CA with a key,
# so the script then makes a throwaway CA, checks curl rejects a server it
# signed, re-runs install.sh with that CA in CERTS (the option variable,
# literal newlines) and checks curl now accepts it.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=ssl-ca-checks.sh
source "$(dirname "$0")/ssl-ca-checks.sh"

check "the static CA from the certs option is in the system bundle" bundle_has "$STATIC_CA_SHA256"
check "it is installed as ssl-ca-<fingerprint>.crt" \
    test -f "/usr/local/share/ca-certificates/ssl-ca-${STATIC_CA_SHA256:0:16}.crt"
check "containerEnv points the CA variables at the system bundle" container_env_ok

ca="$(mktemp -d)/fresh"
make_ca "$ca"
check "curl rejects a server signed by a CA that isn't installed" tls_untrusted "$ca"
check "install.sh with the CA in CERTS (literal newlines) succeeds" \
    rerun_install CERTS="$(cat "${ca}/ca.pem")"
check "the new CA is in the system bundle" bundle_has_pem "${ca}/ca.pem"
check "the earlier CA is kept" bundle_has "$STATIC_CA_SHA256"
check "curl now completes the TLS handshake without -k" tls_trusted "$ca"

reportResults
