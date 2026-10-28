#!/usr/bin/env bash
# The image-environment channel: env_channel/Dockerfile sets
# CLI_POSTGRES_CLIENT_VERSION with ENV, and the scenario sets no options.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=postgres-client-checks.sh
source "$(dirname "$0")/postgres-client-checks.sh"

check "CLI_POSTGRES_CLIENT_VERSION is set in the image" test -n "${CLI_POSTGRES_CLIENT_VERSION:-}"
expect_installed "${CLI_POSTGRES_CLIENT_VERSION:-}"

reportResults
