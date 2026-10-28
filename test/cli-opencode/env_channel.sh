#!/usr/bin/env bash
# The image-environment channel: env_channel/Dockerfile sets CLI_OPENCODE_*
# with ENV, and the scenario sets no options.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=opencode-checks.sh
source "$(dirname "$0")/opencode-checks.sh"

check "CLI_OPENCODE_VERSION is set in the image" test -n "${CLI_OPENCODE_VERSION:-}"
expect_installed "${CLI_OPENCODE_VERSION:-}"

reportResults
