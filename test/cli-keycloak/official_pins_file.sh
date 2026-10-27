#!/usr/bin/env bash
# The pins-file channel at the default path: official_pins_file/Dockerfile
# copies pins.env (flavor, version and sha256) to
# /etc/devcontainer-features/pins.env, and the scenario sets no options.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=keycloak-checks.sh
source "$(dirname "$0")/keycloak-checks.sh"

check "CLI_KEYCLOAK_VERSION is not in the image environment" test -z "${CLI_KEYCLOAK_VERSION:-}"
expect_official "$(pins_value /etc/devcontainer-features/pins.env VERSION)"

reportResults
