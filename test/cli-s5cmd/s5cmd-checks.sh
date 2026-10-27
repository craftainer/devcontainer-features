# shellcheck shell=bash
# Checks shared by the cli-s5cmd scenario scripts. The CLI copies this test
# folder into the test container's workspace, next to the scenario scripts
# and scenarios.json. Source it after dev-container-features-test-lib.

# Prints the "version" option of scenario <name> in scenarios.json.
scenario_version() {
    awk -v name="\"$1\":" '
        $1 == name { inside = 1; next }
        inside && /"version":/ { gsub(/[",]/, "", $2); print $2; exit }
    ' "$(dirname "$0")/scenarios.json"
}

# Prints CLI_S5CMD_VERSION from the pins file <file>.
pins_version() {
    sed -nE 's/^[[:blank:]]*(export[[:blank:]]+)?CLI_S5CMD_VERSION=["'\'']?([^"'\''[:blank:]#]+).*/\2/p' "$1" | tail -n 1
}

_s5cmd_is_local_bin() {
    [ "$(command -v s5cmd)" = /usr/local/bin/s5cmd ]
}

_s5cmd_mode_owner() {
    [ "$(stat -c '%a %u' /usr/local/bin/s5cmd)" = "755 0" ]
}

_s5cmd_reports() {
    local out
    out="$(s5cmd version)"
    echo "s5cmd version: ${out}"
    case "$out" in
        "v$1" | "v$1-"*) return 0 ;;
    esac
    return 1
}

_feature_declares_no_mounts() {
    ! grep -q '"mounts"' "$(dirname "$0")/.devcontainer/cli-s5cmd/devcontainer-feature.json"
}

# expect_installed <version>: s5cmd is /usr/local/bin/s5cmd, root-owned,
# mode 0755, and reports v<version>; the feature declares no mounts.
expect_installed() {
    if [ -z "$1" ]; then
        echo "expect_installed: no expected version" >&2
        return 1
    fi
    check "s5cmd resolves to /usr/local/bin/s5cmd" _s5cmd_is_local_bin
    check "s5cmd is mode 0755, owned by root" _s5cmd_mode_owner
    check "s5cmd reports v$1" _s5cmd_reports "$1"
    check "the feature declares no mounts" _feature_declares_no_mounts
}
