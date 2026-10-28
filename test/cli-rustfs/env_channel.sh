#!/usr/bin/env bash
# The image-environment channel: env_channel/Dockerfile sets CLI_RUSTFS_*
# with ENV, and the scenario sets no options.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=rustfs-checks.sh
source "$(dirname "$0")/rustfs-checks.sh"

check "CLI_RUSTFS_VERSION is set in the image" test -n "${CLI_RUSTFS_VERSION:-}"
expect_installed "${CLI_RUSTFS_VERSION:-}"

reportResults
