#!/usr/bin/env bash
# The rest flavor through the flavor option, with no pin anywhere.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=keycloak-checks.sh
source "$(dirname "$0")/keycloak-checks.sh"

expect_rest

reportResults
