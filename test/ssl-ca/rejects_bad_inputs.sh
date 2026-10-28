#!/usr/bin/env bash
# Negative cases. The scenario installs the static test CA through the
# certs option with \n escapes; this script then re-runs install.sh with
# bad inputs and checks that each run fails with the expected message and
# changes neither the system bundle nor /usr/local/share/ca-certificates.
# An expected failure can't be a scenario of its own, because a failed
# install fails the whole run (ADR 0002).
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=ssl-ca-checks.sh
source "$(dirname "$0")/ssl-ca-checks.sh"

local_dir=/usr/local/share/ca-certificates
check "the static CA from the certs option (\\n escapes) is in the system bundle" \
    bundle_has "$STATIC_CA_SHA256"

zeros="$(printf '%064d' 0)"
scratch="$(mktemp -d)"
chmod 0755 "$scratch"

state() {
    sha256sum "$BUNDLE"
    find "$local_dir" -type f -exec sha256sum {} + 2>/dev/null | sort
}

# expect_rejected <ERE> [VAR=value...]: install.sh, in a clean environment
# with only the given variables, fails with output matching <ERE> and
# leaves the trust store as it was.
expect_rejected() {
    local pattern="$1" before out status=0
    shift
    before="$(state)"
    out="$(rerun_install "$@")" || status=$?
    printf '%s\n' "$out"
    if [ "$status" -eq 0 ]; then
        echo "install.sh succeeded; expected a failure" >&2
        return 1
    fi
    if ! printf '%s\n' "$out" | grep -Eq -- "$pattern"; then
        echo "install.sh output doesn't match: ${pattern}" >&2
        return 1
    fi
    if [ "$(state)" != "$before" ]; then
        echo "install.sh changed the trust store" >&2
        return 1
    fi
}

check "a PEM block that isn't a certificate fails" expect_rejected \
    'the certs feature option, certificate 1 of 1 is not a valid X.509 certificate' \
    CERTS=$'-----BEGIN CERTIFICATE-----\nbm90IGEgY2VydGlmaWNhdGU=\n-----END CERTIFICATE-----'
check "text without any PEM block fails" expect_rejected \
    'the certs feature option: no PEM certificate' \
    CERTS='not a certificate'
check "a BEGIN without END fails" expect_rejected \
    'the certs feature option: a certificate block has no END line' \
    CERTS="$(head -n 3 "${local_dir}/ssl-ca-${STATIC_CA_SHA256:0:16}.crt")"

# A private key pasted by mistake is refused without echoing it.
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "${scratch}/key.pem" 2>/dev/null
key_line="$(sed -n 2p "${scratch}/key.pem")"
private_key_refused() {
    local out status=0
    out="$(rerun_install CERTS="$(cat "${scratch}/key.pem")")" || status=$?
    printf '%s\n' "$out"
    [ "$status" -ne 0 ] || { echo "install.sh accepted a private key" >&2; return 1; }
    printf '%s\n' "$out" | grep -q 'is not a certificate (only CERTIFICATE blocks are accepted)' \
        || { echo "unexpected message" >&2; return 1; }
    if printf '%s\n' "$out" | grep -qF -- "$key_line"; then
        echo "install.sh printed the key material" >&2
        return 1
    fi
}
check "a private key is refused, and its content isn't printed" private_key_refused

check "a URL/sha count mismatch fails" expect_rejected \
    'urls has 2 URL\(s\) but sha256s has 1 sha256\(s\)' \
    URLS="file://${BUNDLE},file://${BUNDLE}" SHA256S="$zeros"
check "a wrong sha fails" expect_rejected \
    "sha256 mismatch for file://${BUNDLE}" \
    URLS="file://${BUNDLE}" SHA256S="$zeros"
check "urls without sha256s fails" expect_rejected \
    'the feature options set urls but not sha256s' \
    URLS="file://${BUNDLE}"
check "urls in the options don't take sha256s from the image environment" expect_rejected \
    'the feature options set urls but not sha256s' \
    URLS="file://${BUNDLE}" SSL_CA_SHA256S="$(sha256sum "$BUNDLE" | cut -d' ' -f1)"
check "SSL_CA_SHA256S without SSL_CA_URLS fails" expect_rejected \
    'the image environment set SSL_CA_SHA256S but not SSL_CA_URLS' \
    SSL_CA_SHA256S="$zeros"
check "an ftp:// URL fails" expect_rejected \
    "'ftp://example.invalid/ca.pem' in urls is not an https://, http:// or file:/// URL" \
    URLS=ftp://example.invalid/ca.pem SHA256S="$zeros"
check "a malformed sha fails" expect_rejected \
    "'not-a-sha' in sha256s is not a sha256" \
    URLS="file://${BUNDLE}" SHA256S=not-a-sha
printf 'not a certificate\n' >"${scratch}/junk.txt"
check "a URL that serves neither PEM nor DER fails" expect_rejected \
    "file://${scratch}/junk.txt: neither PEM .* nor a DER certificate" \
    URLS="file://${scratch}/junk.txt" SHA256S="$(sha256sum "${scratch}/junk.txt" | cut -d' ' -f1)"

# A pre-placed .crt with two certificates would be skipped by
# update-ca-certificates, so it fails instead.
two_certs_preplaced() {
    local f="${local_dir}/zz-two.crt" result=0
    as_root sh -c "cat '${local_dir}/ssl-ca-${STATIC_CA_SHA256:0:16}.crt' '${local_dir}/ssl-ca-${STATIC_CA_SHA256:0:16}.crt' >'$f'"
    rerun_install >"${scratch}/two.out" 2>&1 && result=1
    cat "${scratch}/two.out"
    grep -q "${f} holds 2 certificates" "${scratch}/two.out" || result=1
    as_root rm -f "$f"
    return "$result"
}
check "a pre-placed .crt holding two certificates fails" two_certs_preplaced

# Nothing at all: no option, no variable, no pins file and no *.crt.
nothing_supplied() {
    local result=0
    as_root mv "$local_dir" "${local_dir}.aside"
    expect_rejected \
        'no CA certificate given: set the certs option \(inline PEM\) or the urls and sha256s options, or SSL_CA_CERTS / SSL_CA_URLS and SSL_CA_SHA256S in the image environment or in the pins file /etc/devcontainer-features/pins.env \(not found\), or put \*.crt files in /usr/local/share/ca-certificates' \
        || result=1
    as_root mv "${local_dir}.aside" "$local_dir"
    return "$result"
}
check "nothing supplied fails, naming every channel" nothing_supplied

# A pins_file option naming a missing file warns, even though certs
# supplies a certificate and the install succeeds.
missing_pins_file_warns() {
    local out status=0
    out="$(rerun_install PINS_FILE=/nonexistent/pins.env \
        CERTS="$(cat "${local_dir}/ssl-ca-${STATIC_CA_SHA256:0:16}.crt")")" || status=$?
    printf '%s\n' "$out"
    [ "$status" -eq 0 ] || { echo "install.sh failed" >&2; return 1; }
    grep -qF 'ssl-ca: warning: the pins_file option names /nonexistent/pins.env, which doesn'"'"'t exist' <<<"$out"
}
check "a pins_file option naming a missing file warns, and certs still install" missing_pins_file_warns

rm -rf "$scratch"

reportResults
