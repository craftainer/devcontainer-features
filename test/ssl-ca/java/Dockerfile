# Java: a JRE is installed before the feature (the only scenario that
# does, since it is heavy), and the throwaway CA comes from the pins file.
# The feature must import it into the JDK's cacerts.
ARG BASE_IMAGE
FROM ${BASE_IMAGE}

RUN set -eu; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends default-jre-headless openssl; \
    rm -rf /var/lib/apt/lists/*; \
    d=/opt/ssl-ca-test/java; \
    mkdir -p "$d" /etc/devcontainer-features; \
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
        -keyout "$d/ca.key" -out "$d/ca.pem" -days 30 -subj "/CN=ssl-ca java test CA" \
        -addext basicConstraints=critical,CA:TRUE -addext keyUsage=critical,keyCertSign,cRLSign; \
    chmod -R a+rX /opt/ssl-ca-test; \
    { printf 'SSL_CA_CERTS="'; awk '{ printf "%s\\n", $0 }' "$d/ca.pem"; printf '"\n'; } \
        >/etc/devcontainer-features/pins.env
