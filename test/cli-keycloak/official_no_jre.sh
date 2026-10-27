#!/usr/bin/env bash
# official with install_jre false, on an image without Java: kcadm is
# installed, nothing installs Java, and kcadm is not run.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=keycloak-checks.sh
source "$(dirname "$0")/keycloak-checks.sh"

expect_official "$(scenario_version official_no_jre)" no-jre

reportResults
