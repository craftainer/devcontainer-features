# Writes this distro's pin to a pins file (PINS_PATH, by default the
# feature's default path). repo.mosquitto.org (Debian) and Ubuntu's archive
# carry different Mosquitto versions (src/cli-mosquitto/NOTES.md), so no
# single pin fits the CI matrix's Debian and Ubuntu images: scenarios.json
# passes one per distro, and this picks it from ID in /etc/os-release.
ARG BASE_IMAGE
FROM ${BASE_IMAGE}

ARG CLI_MOSQUITTO_VERSION_DEBIAN
ARG CLI_MOSQUITTO_VERSION_UBUNTU
ARG PINS_PATH=/etc/devcontainer-features/pins.env
RUN set -eu; \
    id="$(. /etc/os-release && echo "$ID")"; \
    case "$id" in \
        debian) v="$CLI_MOSQUITTO_VERSION_DEBIAN" ;; \
        ubuntu) v="$CLI_MOSQUITTO_VERSION_UBUNTU" ;; \
        *) echo "no cli-mosquitto test pin for ID=${id}" >&2; exit 1 ;; \
    esac; \
    test -n "$v"; \
    mkdir -p "$(dirname "$PINS_PATH")"; \
    printf '# The %s pin, written by the scenario Dockerfile.\nCLI_OTHER_VERSION=9.9.9\nCLI_MOSQUITTO_VERSION=%s\n' \
        "$id" "$v" >"$PINS_PATH"
