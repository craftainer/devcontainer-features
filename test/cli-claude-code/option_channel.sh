#!/usr/bin/env bash
# The feature-options channel: version and per-arch shas set as options in
# scenarios.json.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=claude-code-checks.sh
source "$(dirname "$0")/claude-code-checks.sh"

expect_installed "$(scenario_version option_channel)"

reportResults
