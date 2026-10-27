#!/usr/bin/env bash
# official with install_jre false while JAVA_HOME points at a fake Java 17
# (official_old_java/Dockerfile): the install warns and succeeds, kcadm is
# installed, no JRE is added, and kcadm.sh is not run.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=keycloak-checks.sh
source "$(dirname "$0")/keycloak-checks.sh"

check "JAVA_HOME is the fake Java 17" test "${JAVA_HOME:-}" = /opt/fake-jdk-17
expect_official "${CLI_KEYCLOAK_VERSION:-}" no-jre

reportResults
