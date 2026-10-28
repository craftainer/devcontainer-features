# The pins-file channel: a throwaway CA is made at build time (its key
# stays in this test image only, for the TLS check), and the default pins
# file holds its PEM as SSL_CA_CERTS on one line with \n escapes, quoted.
ARG BASE_IMAGE
FROM ${BASE_IMAGE}

RUN set -eu; \
    if ! command -v openssl >/dev/null; then \
        apt-get update; \
        DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends openssl; \
        rm -rf /var/lib/apt/lists/*; \
    fi; \
    d=/opt/ssl-ca-test/pins; \
    mkdir -p "$d" /etc/devcontainer-features; \
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
        -keyout "$d/ca.key" -out "$d/ca.pem" -days 30 -subj "/CN=ssl-ca pins-file test CA" \
        -addext basicConstraints=critical,CA:TRUE -addext keyUsage=critical,keyCertSign,cRLSign; \
    chmod -R a+rX /opt/ssl-ca-test; \
    { printf '# test pins\nSSL_CA_CERTS="'; awk '{ printf "%s\\n", $0 }' "$d/ca.pem"; printf '"\n'; } \
        >/etc/devcontainer-features/pins.env; \
    cat /etc/devcontainer-features/pins.env
