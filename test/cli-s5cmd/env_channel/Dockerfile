# The image-environment channel: the pin comes from ENV lines in the base
# image, and the scenario sets no options.
ARG BASE_IMAGE
FROM ${BASE_IMAGE}

# renovate: datasource=github-releases depName=peak/s5cmd extractVersion=^v(?<version>.+)$
ENV CLI_S5CMD_VERSION=2.3.0
ENV CLI_S5CMD_SHA256_AMD64=de0fdbfa3aceae55e069ba81a0fc17b2026567637603734a387b2fca06c299b4
ENV CLI_S5CMD_SHA256_ARM64=1439f0d00ecedcd2a2f1f2c6749bbb0152b2257bf5086f29646ec8ae38798e24
