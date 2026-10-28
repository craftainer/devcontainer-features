#!/usr/bin/env bash
# Java: java/Dockerfile installs default-jre-headless before the feature,
# and the throwaway CA comes from the pins file. The CA must be in every
# JDK cacerts, and a re-run must not add it twice.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=ssl-ca-checks.sh
source "$(dirname "$0")/ssl-ca-checks.sh"

ca=/opt/ssl-ca-test/java
fp="$(fingerprint "${ca}/ca.pem")"
fp_colons="$(sed 's/../&:/g; s/:$//' <<<"${fp^^}")"

# count_in_stores: prints, per JDK cacerts, how often the CA's fingerprint
# appears in keytool -list -v; fails if there is no store.
count_in_stores() {
    local store count found=0
    for store in /usr/lib/jvm/*/lib/security/cacerts; do
        [ -e "$store" ] || continue
        found=1
        count="$(keytool -list -v -keystore "$store" -storepass changeit 2>/dev/null \
            | grep -c "SHA256: ${fp_colons}" || true)"
        printf '%s %s\n' "$store" "$count"
    done
    [ "$found" -eq 1 ]
}

# in_every_store: the CA is in each JDK cacerts exactly once.
in_every_store() {
    local out
    out="$(count_in_stores)" || { echo "no JDK cacerts under /usr/lib/jvm" >&2; return 1; }
    printf '%s\n' "$out"
    ! printf '%s\n' "$out" | grep -qv ' 1$'
}

check "the CA is in the system bundle" bundle_has_pem "${ca}/ca.pem"
check "the CA is in every JDK cacerts, exactly once" in_every_store
check "a re-run of install.sh succeeds" rerun_install \
    SSL_CA_CERTS="$(escape_newlines "${ca}/ca.pem")"
check "after the re-run the CA is still in every JDK cacerts exactly once" in_every_store

# Debian's ca-certificates-java hook already adds the CA to the shared
# /etc/ssl/certs/java/cacerts during update-ca-certificates, so the
# feature's own import is exercised with a second, unshared store: a fake
# JDK with its own cacerts (holding one unrelated certificate) and its own
# bin/keytool.
fake=/usr/lib/jvm/zz-ssl-ca-test-jdk
fake_store_import() {
    local other out
    other="$(mktemp -d)/other"
    make_ca "$other" || return 1
    as_root mkdir -p "${fake}/lib/security" "${fake}/bin"
    as_root ln -sf "$(readlink -f "$(command -v keytool)")" "${fake}/bin/keytool"
    as_root keytool -importcert -noprompt -alias unrelated -file "${other}/ca.pem" \
        -keystore "${fake}/lib/security/cacerts" -storetype PKCS12 -storepass changeit >/dev/null 2>&1 || return 1
    out="$(rerun_install SSL_CA_CERTS="$(escape_newlines "${ca}/ca.pem")")" || {
        printf '%s\n' "$out"
        return 1
    }
    printf '%s\n' "$out"
    grep -q "${fake}/lib/security/cacerts (keytool ${fake}/bin/keytool): 1 imported" <<<"$out"
}
check "a JDK with its own cacerts gets the CA through its own keytool" fake_store_import
check "the CA is in every JDK cacerts, including that one, exactly once" in_every_store
check "another re-run imports nothing new" rerun_install \
    SSL_CA_CERTS="$(escape_newlines "${ca}/ca.pem")"
check "the CA is still in every JDK cacerts exactly once" in_every_store
as_root rm -rf "$fake"
check "containerEnv points the CA variables at the system bundle" container_env_ok

reportResults
