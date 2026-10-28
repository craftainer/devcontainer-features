# ssl-ca, then cli-s5cmd: a throwaway CA is made at build time (its key
# stays in this test image only, for the TLS checks) and handed to ssl-ca
# through the default pins file, which also holds nothing for cli-s5cmd
# (its pin comes from the scenario's options).
ARG BASE_IMAGE
FROM ${BASE_IMAGE}

RUN set -eu; \
    if ! command -v openssl >/dev/null; then \
        apt-get update; \
        DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends openssl; \
        rm -rf /var/lib/apt/lists/*; \
    fi; \
    d=/opt/ssl-ca-test/global; \
    mkdir -p "$d" /etc/devcontainer-features; \
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
        -keyout "$d/ca.key" -out "$d/ca.pem" -days 30 -subj "/CN=ssl-ca global test CA" \
        -addext basicConstraints=critical,CA:TRUE -addext keyUsage=critical,keyCertSign,cRLSign; \
    chmod -R a+rX /opt/ssl-ca-test; \
    { printf 'SSL_CA_CERTS="'; awk '{ printf "%s\\n", $0 }' "$d/ca.pem"; printf '"\n'; } \
        >/etc/devcontainer-features/pins.env
