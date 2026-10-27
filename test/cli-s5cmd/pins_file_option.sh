#!/usr/bin/env bash
# The pins-file channel at the path set by the pins_file option:
# pins_file_option/Dockerfile copies pins.env (export form, a quoted value,
# trailing comments) to /opt/pins/s5cmd.env.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=s5cmd-checks.sh
source "$(dirname "$0")/s5cmd-checks.sh"

check "there is no pins file at the default path" test ! -e /etc/devcontainer-features/pins.env
expect_installed "$(pins_version /opt/pins/s5cmd.env)"

reportResults
