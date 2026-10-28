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

# An https CA URL behind a TLS-intercepting proxy: the server's leaf is
# signed by a "proxy" CA that only the certs input supplies, and it serves
# the CA certificate the URL points at. install.sh installs certs before
# fetching URLs, so the download must succeed with that CA, and fail at the
# fetch without it. Both CAs are fresh, so neither is trusted beforehand;
# the run without the proxy CA comes first.
scratch="$(mktemp -d)"
make_ca "${scratch}/proxy"
make_ca "${scratch}/target"
mkdir "${scratch}/www"
cp "${scratch}/target/ca.pem" "${scratch}/www/target.pem"
chmod -R a+rX "$scratch"
target_sha="$(sha256sum "${scratch}/www/target.pem" | cut -d' ' -f1)"

# https_url_run [VAR=value...]: re-runs install.sh with the https URL and
# its sha plus the given variables, while the proxy-signed server runs.
https_url_run() {
    local status=0
    start_https_server "${scratch}/proxy" "${scratch}/www" || return 1
    rerun_install URLS="https://localhost:${server_port}/target.pem" SHA256S="$target_sha" "$@" \
        || status=$?
    stop_https_server
    return "$status"
}

https_url_without_proxy_ca() {
    local out status=0
    out="$(https_url_run CERTS=)" || status=$?
    printf '%s\n' "$out"
    [ "$status" -ne 0 ] || { echo "install.sh succeeded without the proxy CA" >&2; return 1; }
    # curl exit 60: the server's certificate can't be verified.
    grep -Eq 'download failed \(curl exit 60' <<<"$out" \
        || { echo "install.sh didn't fail at the fetch with a certificate error" >&2; return 1; }
}
check "an https URL signed by an untrusted proxy CA fails at the fetch" https_url_without_proxy_ca
not_in_bundle() { ! bundle_has_pem "$1" 2>/dev/null; }
check "the URL's CA isn't installed after that failure" not_in_bundle "${scratch}/target/ca.pem"
check "with the proxy CA in certs, the same https URL is fetched and installed" \
    https_url_run CERTS="$(cat "${scratch}/proxy/ca.pem")"
check "the proxy CA from certs is in the system bundle" bundle_has_pem "${scratch}/proxy/ca.pem"
check "the CA fetched over https is in the system bundle" bundle_has_pem "${scratch}/target/ca.pem"
rm -rf "$scratch"

reportResults
