#!/usr/bin/env bash
# The feature-options channel: the version is set as an option in
# scenarios.json.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=postgres-client-checks.sh
source "$(dirname "$0")/postgres-client-checks.sh"

expect_installed "$(scenario_version option_channel)"

reportResults
