#!/usr/bin/env bash
# The feature's metadata and container environment: it declares no mounts
# and no CLAUDE_CONFIG_DIR (state handling is the consumer's choice, see
# NOTES.md), and it turns off the auto-updater and the manual updates with
# DISABLE_AUTOUPDATER=1 and DISABLE_UPDATES=1 in containerEnv, so claude
# stays at the pinned version.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=claude-code-checks.sh
source "$(dirname "$0")/claude-code-checks.sh"

_json_declares_no_mounts() {
    ! grep -q '"mounts"' "$(feature_json)"
}

_json_sets_no_claude_config_dir() {
    ! grep -q CLAUDE_CONFIG_DIR "$(feature_json)"
}

_json_has_containerenv_update_switches() {
    local env
    env="$(tr -d ' \n' <"$(feature_json)" | grep -o '"containerEnv":{[^}]*}')" || return 1
    grep -q '"DISABLE_AUTOUPDATER":"1"' <<<"$env" && grep -q '"DISABLE_UPDATES":"1"' <<<"$env"
}

expect_installed "$(scenario_version container_env)"
check "devcontainer-feature.json is in the workspace" test -f "$(feature_json)"
check "devcontainer-feature.json declares no mounts" _json_declares_no_mounts
check "devcontainer-feature.json sets no CLAUDE_CONFIG_DIR" _json_sets_no_claude_config_dir
check "devcontainer-feature.json sets DISABLE_AUTOUPDATER=1 and DISABLE_UPDATES=1 in containerEnv" _json_has_containerenv_update_switches
check "DISABLE_AUTOUPDATER=1 is in the container environment" test "${DISABLE_AUTOUPDATER:-}" = 1
check "DISABLE_UPDATES=1 is in the container environment" test "${DISABLE_UPDATES:-}" = 1
check "CLAUDE_CONFIG_DIR is not in the container environment" test -z "${CLAUDE_CONFIG_DIR+set}"

reportResults
