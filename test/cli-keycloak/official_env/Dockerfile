# The image-environment channel: the pin comes from ENV lines in the base
# image, and the scenario sets no options, so the flavor is the default
# (official).
ARG BASE_IMAGE
FROM ${BASE_IMAGE}

# renovate: datasource=github-releases depName=keycloak/keycloak
ENV CLI_KEYCLOAK_VERSION=26.7.5
ENV CLI_KEYCLOAK_SHA256=87d680d13cf4600d232ca0433a2553c57ebf03e56f7718fc0d03a1a8705497c8
