#!/usr/bin/env bash
# The feature-options channel: version and per-arch shas set as options in
# scenarios.json.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=rustfs-checks.sh
source "$(dirname "$0")/rustfs-checks.sh"

expect_installed "$(scenario_version option_channel)"
expect_license_notice /usr/local/share/doc/rustfs-cli/LICENSE-MIT "Permission is hereby granted"
expect_license_notice /usr/local/share/doc/rustfs-cli/LICENSE-APACHE "Apache License"

reportResults
