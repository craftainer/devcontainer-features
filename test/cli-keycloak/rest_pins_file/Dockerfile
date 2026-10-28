# The pins-file channel for the flavor: rest is selected only by
# CLI_KEYCLOAK_FLAVOR in the default pins file. This guards install.sh's use
# of install-lib's private _il_pins_get.
ARG BASE_IMAGE
FROM ${BASE_IMAGE}

COPY pins.env /etc/devcontainer-features/pins.env
