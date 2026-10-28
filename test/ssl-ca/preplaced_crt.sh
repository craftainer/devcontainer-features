#!/usr/bin/env bash
# A pre-placed certificate only: preplaced_crt/Dockerfile puts a throwaway
# CA in /usr/local/share/ca-certificates/corp/, and the feature gets no
# certs or urls.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=ssl-ca-checks.sh
source "$(dirname "$0")/ssl-ca-checks.sh"

ca=/opt/ssl-ca-test/preplaced
check "the pre-placed file is kept" test -f /usr/local/share/ca-certificates/corp/corp-root.crt
check "the pre-placed CA is in the system bundle" bundle_has_pem "${ca}/ca.pem"
check "containerEnv points the CA variables at the system bundle" container_env_ok
check "curl completes a TLS handshake with a server that CA signed, without -k" tls_trusted "$ca"
other="$(mktemp -d)/other"
make_ca "$other"
check "curl still rejects a server signed by a CA that isn't installed" tls_untrusted "$other"

reportResults
