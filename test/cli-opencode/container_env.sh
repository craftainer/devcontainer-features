#!/usr/bin/env bash
# The feature's metadata and container environment: it declares no mounts
# and no state-path variable (OPENCODE_CONFIG_DIR, OPENCODE_CONFIG or the
# XDG_* base directories; state handling is the consumer's choice, see
# NOTES.md), and it turns off opencode's update checks with
# OPENCODE_DISABLE_AUTOUPDATE=1 in containerEnv, so opencode stays at the
# pinned version.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=opencode-checks.sh
source "$(dirname "$0")/opencode-checks.sh"

_json_declares_no_mounts() {
    ! grep -q '"mounts"' "$(feature_json)"
}

_json_sets_no_state_path() {
    ! grep -Eq 'OPENCODE_CONFIG|XDG_' "$(feature_json)"
}

_json_has_containerenv_autoupdate() {
    tr -d ' \n' <"$(feature_json)" | grep -q '"containerEnv":{"OPENCODE_DISABLE_AUTOUPDATE":"1"}'
}

expect_installed "$(scenario_version container_env)"
check "devcontainer-feature.json is in the workspace" test -f "$(feature_json)"
check "devcontainer-feature.json declares no mounts" _json_declares_no_mounts
check "devcontainer-feature.json sets no OPENCODE_CONFIG* or XDG_* variable" _json_sets_no_state_path
check "devcontainer-feature.json sets OPENCODE_DISABLE_AUTOUPDATE=1 in containerEnv" _json_has_containerenv_autoupdate
check "OPENCODE_DISABLE_AUTOUPDATE=1 is in the container environment" test "${OPENCODE_DISABLE_AUTOUPDATE:-}" = 1
check "OPENCODE_CONFIG_DIR is not in the container environment" test -z "${OPENCODE_CONFIG_DIR+set}"

reportResults
