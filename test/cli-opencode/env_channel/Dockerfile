# The image-environment channel: the pin comes from ENV lines in the base
# image, and the scenario sets no options.
ARG BASE_IMAGE
FROM ${BASE_IMAGE}

# renovate: datasource=github-releases depName=anomalyco/opencode extractVersion=^v(?<version>.*)$
ENV CLI_OPENCODE_VERSION=1.19.5
ENV CLI_OPENCODE_SHA256_AMD64=588310a336fa3b9df36b3f0225b26f679d453efaad0cf3d66c3651ef3ec1647a
ENV CLI_OPENCODE_SHA256_ARM64=fae5be262d693b7c5e562856cc473e59e741772936db0c0600ac0d5ed5bd088b
