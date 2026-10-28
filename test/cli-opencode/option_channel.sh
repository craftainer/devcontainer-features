#!/usr/bin/env bash
# The feature-options channel: version and per-arch shas set as options in
# scenarios.json.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=opencode-checks.sh
source "$(dirname "$0")/opencode-checks.sh"

expect_installed "$(scenario_version option_channel)"

reportResults
