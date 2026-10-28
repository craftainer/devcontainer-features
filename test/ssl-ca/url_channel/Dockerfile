# The URL channel: two throwaway CAs are made at build time (their keys
# stay in this test image only, for the TLS checks), one served as PEM and
# one as DER through file:// URLs, so the test needs no network for them.
# The scenario's pins_file option points at a non-default pins file with
# SSL_CA_URLS and SSL_CA_SHA256S (comma- and blank-separated).
ARG BASE_IMAGE
FROM ${BASE_IMAGE}

RUN set -eu; \
    if ! command -v openssl >/dev/null; then \
        apt-get update; \
        DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends openssl; \
        rm -rf /var/lib/apt/lists/*; \
    fi; \
    for n in pem der; do \
        d="/opt/ssl-ca-test/url-$n"; \
        mkdir -p "$d"; \
        openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
            -keyout "$d/ca.key" -out "$d/ca.pem" -days 30 -subj "/CN=ssl-ca url test CA ($n)" \
            -addext basicConstraints=critical,CA:TRUE -addext keyUsage=critical,keyCertSign,cRLSign; \
    done; \
    openssl x509 -in /opt/ssl-ca-test/url-der/ca.pem -outform DER -out /opt/ssl-ca-test/url-der/ca.der; \
    chmod -R a+rX /opt/ssl-ca-test; \
    pem_sha="$(sha256sum /opt/ssl-ca-test/url-pem/ca.pem | cut -d' ' -f1)"; \
    der_sha="$(sha256sum /opt/ssl-ca-test/url-der/ca.der | cut -d' ' -f1)"; \
    printf 'SSL_CA_URLS="file:///opt/ssl-ca-test/url-pem/ca.pem, file:///opt/ssl-ca-test/url-der/ca.der"\nSSL_CA_SHA256S="%s %s"\n' \
        "$pem_sha" "$der_sha" >/opt/ssl-ca-test/urls.env; \
    cat /opt/ssl-ca-test/urls.env
