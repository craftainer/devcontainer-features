#!/usr/bin/env bash
# The pins-file channel at the default path: pins_file_channel/Dockerfile
# copies pins.env to /etc/devcontainer-features/pins.env, and the scenario
# sets no options.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=valkey-checks.sh
source "$(dirname "$0")/valkey-checks.sh"

check "CLI_VALKEY_VERSION is not in the image environment" test -z "${CLI_VALKEY_VERSION:-}"
expect_installed "$(pins_version /etc/devcontainer-features/pins.env)"

reportResults
