# The image-environment channel: the pin comes from an ENV line in the base
# image, and the scenario sets no options.
ARG BASE_IMAGE
FROM ${BASE_IMAGE}

# renovate: datasource=docker depName=postgres
ENV CLI_POSTGRES_CLIENT_VERSION=18.6
