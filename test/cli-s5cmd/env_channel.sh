#!/usr/bin/env bash
# The image-environment channel: env_channel/Dockerfile sets CLI_S5CMD_*
# with ENV, and the scenario sets no options.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=s5cmd-checks.sh
source "$(dirname "$0")/s5cmd-checks.sh"

check "CLI_S5CMD_VERSION is set in the image" test -n "${CLI_S5CMD_VERSION:-}"
expect_installed "${CLI_S5CMD_VERSION:-}"

reportResults
