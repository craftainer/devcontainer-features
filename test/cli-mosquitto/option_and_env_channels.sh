#!/usr/bin/env bash
# The feature-options and image-environment channels. A static option or
# ENV line can't fit both the Debian and the Ubuntu images of the CI matrix
# (their Mosquitto versions differ), so the build installs this distro's
# pin from the pins file, as in pins_file_channel, and this script then
# purges the clients and runs the feature's install.sh again: once with
# the version option ($VERSION, as the Dev Container CLI passes it) and
# once with CLI_MOSQUITTO_VERSION in the environment. The pins file is
# pointed at a missing path for those runs, so only the channel under test
# can supply the pin, and install-lib's log names the channel it used.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=mosquitto-checks.sh
source "$(dirname "$0")/mosquitto-checks.sh"

version="$(pins_version /etc/devcontainer-features/pins.env)"
check "this distro's pin is in the pins file" test -n "$version"
expect_installed "$version"

# install_via <channel description> <VAR=value>: purges the clients, runs
# install.sh with only <VAR=value> and a missing pins file, and succeeds
# when it installs and logs the pin as coming from <channel description>.
install_via() {
    local channel="$1" out status=0
    purge_clients
    if clients_installed; then
        echo "mosquitto-clients is still installed after the purge" >&2
        return 1
    fi
    out="$(run_install PINS_FILE=/nonexistent/pins.env "$2" 2>&1)" || status=$?
    printf '%s\n' "$out" | tail -n 3
    [ "$status" -eq 0 ] || return 1
    printf '%s\n' "$out" | grep -Fqx "install-lib: CLI_MOSQUITTO ${version} (from ${channel})"
}

check "the version option installs ${version}" install_via "the feature options" VERSION="$version"
expect_installed "$version"

check "CLI_MOSQUITTO_VERSION in the environment installs ${version}" \
    install_via "the image environment" CLI_MOSQUITTO_VERSION="$version"
expect_installed "$version"

reportResults
