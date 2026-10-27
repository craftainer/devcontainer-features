#!/usr/bin/env bash
# The rest flavor selected only by CLI_KEYCLOAK_FLAVOR in the default pins
# file (rest_pins_file/pins.env). install.sh reads it with install-lib's
# private _il_pins_get; this scenario fails if a library change breaks that.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=keycloak-checks.sh
source "$(dirname "$0")/keycloak-checks.sh"

check "CLI_KEYCLOAK_FLAVOR is not in the image environment" test -z "${CLI_KEYCLOAK_FLAVOR:-}"
check "the pins file selects rest" test "$(pins_value /etc/devcontainer-features/pins.env FLAVOR)" = rest
expect_rest

reportResults
