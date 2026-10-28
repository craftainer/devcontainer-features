#!/usr/bin/env bash
# The image-environment channel: env_channel/Dockerfile sets CLI_VALKEY_*
# with ENV, and the scenario sets no options.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=valkey-checks.sh
source "$(dirname "$0")/valkey-checks.sh"

check "CLI_VALKEY_VERSION is set in the image" test -n "${CLI_VALKEY_VERSION:-}"
expect_installed "${CLI_VALKEY_VERSION:-}"

reportResults
