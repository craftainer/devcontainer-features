#!/usr/bin/env bash
# The rest flavor through CLI_KEYCLOAK_FLAVOR in the image environment
# (rest_env/Dockerfile), with no options and no pin.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=keycloak-checks.sh
source "$(dirname "$0")/keycloak-checks.sh"

check "CLI_KEYCLOAK_FLAVOR is rest in the image" test "${CLI_KEYCLOAK_FLAVOR:-}" = rest
expect_rest

reportResults
