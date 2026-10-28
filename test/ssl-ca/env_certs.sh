#!/usr/bin/env bash
# The image-environment channel: env_certs/Dockerfile sets SSL_CA_CERTS to
# the static test CA with \n escapes. The TLS handshake uses a throwaway
# CA passed the same way (SSL_CA_CERTS, \n escapes) to a re-run of
# install.sh, since the static CA has no key.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=ssl-ca-checks.sh
source "$(dirname "$0")/ssl-ca-checks.sh"

has_escapes() {
    [[ "${SSL_CA_CERTS:-}" == *'\n'* ]] && [[ "${SSL_CA_CERTS:-}" != *$'\n'* ]]
}
check "SSL_CA_CERTS is set in the image, on one line with \\n escapes" has_escapes
check "the static CA from SSL_CA_CERTS is in the system bundle" bundle_has "$STATIC_CA_SHA256"
check "containerEnv points the CA variables at the system bundle" container_env_ok

ca="$(mktemp -d)/fresh"
make_ca "$ca"
check "curl rejects a server signed by a CA that isn't installed" tls_untrusted "$ca"
check "install.sh with the CA in SSL_CA_CERTS (\\n escapes) succeeds" \
    rerun_install SSL_CA_CERTS="$(escape_newlines "${ca}/ca.pem")"
check "the new CA is in the system bundle" bundle_has_pem "${ca}/ca.pem"
check "curl now completes the TLS handshake without -k" tls_trusted "$ca"

reportResults
