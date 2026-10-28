#!/usr/bin/env bash
# The feature-options channel: version and per-arch shas set as options in
# scenarios.json. Also runs valkey-cli against a throwaway local
# valkey-server taken from the same release tarball (not installed).
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=valkey-checks.sh
source "$(dirname "$0")/valkey-checks.sh"

expect_installed "$(scenario_version option_channel)"
check "valkey-cli talks to a local valkey-server, with REDISCLI_AUTH and VALKEYCLI_AUTH" \
    valkey_server_smoke "$(scenario_version option_channel)" \
    "$(scenario_option option_channel sha256_amd64)" \
    "$(scenario_option option_channel sha256_arm64)"

reportResults
