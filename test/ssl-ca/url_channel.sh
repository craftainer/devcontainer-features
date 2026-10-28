#!/usr/bin/env bash
# The URL channel: url_channel/Dockerfile serves two throwaway CAs (PEM
# and DER) as file:// URLs, listed with their shas in the pins file that
# the scenario's pins_file option names.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=ssl-ca-checks.sh
source "$(dirname "$0")/ssl-ca-checks.sh"

check "the CA fetched as PEM is in the system bundle" bundle_has_pem /opt/ssl-ca-test/url-pem/ca.pem
check "the CA fetched as DER is in the system bundle" bundle_has_pem /opt/ssl-ca-test/url-der/ca.pem
check "containerEnv points the CA variables at the system bundle" container_env_ok
check "curl trusts a server signed by the PEM CA" tls_trusted /opt/ssl-ca-test/url-pem
check "curl trusts a server signed by the DER CA" tls_trusted /opt/ssl-ca-test/url-der
other="$(mktemp -d)/other"
make_ca "$other"
check "curl still rejects a server signed by a CA that isn't installed" tls_untrusted "$other"

reportResults
