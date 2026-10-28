# A pre-placed certificate only: the consumer's Dockerfile puts a CA in a
# subdirectory of /usr/local/share/ca-certificates (as a COPY would), and
# the feature gets no certs or urls. The throwaway CA is made at build
# time; its key stays in this test image only, for the TLS check.
ARG BASE_IMAGE
FROM ${BASE_IMAGE}

RUN set -eu; \
    if ! command -v openssl >/dev/null; then \
        apt-get update; \
        DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends openssl; \
        rm -rf /var/lib/apt/lists/*; \
    fi; \
    d=/opt/ssl-ca-test/preplaced; \
    mkdir -p "$d" /usr/local/share/ca-certificates/corp; \
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
        -keyout "$d/ca.key" -out "$d/ca.pem" -days 30 -subj "/CN=ssl-ca pre-placed test CA" \
        -addext basicConstraints=critical,CA:TRUE -addext keyUsage=critical,keyCertSign,cRLSign; \
    chmod -R a+rX /opt/ssl-ca-test; \
    cp "$d/ca.pem" /usr/local/share/ca-certificates/corp/corp-root.crt
