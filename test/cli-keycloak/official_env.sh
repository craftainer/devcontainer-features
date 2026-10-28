#!/usr/bin/env bash
# The image-environment channel: official_env/Dockerfile sets
# CLI_KEYCLOAK_VERSION and CLI_KEYCLOAK_SHA256 with ENV, and the scenario
# sets no options.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=keycloak-checks.sh
source "$(dirname "$0")/keycloak-checks.sh"

check "CLI_KEYCLOAK_VERSION is set in the image" test -n "${CLI_KEYCLOAK_VERSION:-}"
expect_official "${CLI_KEYCLOAK_VERSION:-}"

reportResults
