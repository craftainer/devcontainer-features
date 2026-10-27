# official with install_jre false on an image whose JAVA_HOME holds a
# "Java 17": a fake java, a small script that reports version 17 (no JDK
# download). The install must warn and still succeed. The pin comes from
# the image environment.
ARG BASE_IMAGE
FROM ${BASE_IMAGE}

RUN mkdir -p /opt/fake-jdk-17/bin \
    && printf '%s\n' '#!/bin/sh' \
        'echo "    java.specification.version = 17" >&2' \
        'echo "openjdk version \"17.0.9\"" >&2' >/opt/fake-jdk-17/bin/java \
    && chmod 0755 /opt/fake-jdk-17/bin/java
ENV JAVA_HOME=/opt/fake-jdk-17

# renovate: datasource=github-releases depName=keycloak/keycloak
ENV CLI_KEYCLOAK_VERSION=26.7.5
ENV CLI_KEYCLOAK_SHA256=87d680d13cf4600d232ca0433a2553c57ebf03e56f7718fc0d03a1a8705497c8
