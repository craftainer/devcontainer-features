#!/usr/bin/env bash
# The pins-file channel: pins_file_channel/Dockerfile makes a throwaway CA
# and writes it to /etc/devcontainer-features/pins.env as SSL_CA_CERTS.
# This also covers install.sh's use of install-lib's private _il_pins_get.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=ssl-ca-checks.sh
source "$(dirname "$0")/ssl-ca-checks.sh"

ca=/opt/ssl-ca-test/pins
check "the pins-file CA is in the system bundle" bundle_has_pem "${ca}/ca.pem"
check "containerEnv points the CA variables at the system bundle" container_env_ok
check "curl completes a TLS handshake with a server that CA signed, without -k" tls_trusted "$ca"
other="$(mktemp -d)/other"
make_ca "$other"
check "curl still rejects a server signed by a CA that isn't installed" tls_untrusted "$other"

reportResults
