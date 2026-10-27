#!/usr/bin/env bash
# The feature-options channel: version and sha256 set as options, no
# flavor (so the default, official) and the default install_jre (true).
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=keycloak-checks.sh
source "$(dirname "$0")/keycloak-checks.sh"

expect_official "$(scenario_version official_option)"

reportResults
