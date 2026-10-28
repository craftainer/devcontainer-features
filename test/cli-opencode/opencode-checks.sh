# shellcheck shell=bash
# Checks shared by the cli-opencode scenario scripts. The CLI copies this
# test folder into the test container's workspace, next to the scenario
# scripts and scenarios.json. Source it after dev-container-features-test-lib.
# Nothing here runs opencode against the network: --version only.

# Prints the cli-opencode "version" option of scenario <name> in
# scenarios.json. The search stops at the scenario's closing brace (a line
# holding only "}," or "}" at the scenario's two-space indent), so a
# scenario without a version prints nothing rather than the next one's.
scenario_version() {
    awk -v name="\"$1\":" '
        $1 == name { inside = 1; next }
        inside && /^  },?[[:space:]]*$/ { exit }
        inside && /"version":/ { gsub(/[",]/, "", $2); print $2; exit }
    ' "$(dirname "$0")/scenarios.json"
}

# Prints CLI_OPENCODE_VERSION from the pins file <file>.
pins_version() {
    sed -nE 's/^[[:blank:]]*(export[[:blank:]]+)?CLI_OPENCODE_VERSION=["'\'']?([^"'\''[:blank:]#]+).*/\2/p' "$1" | tail -n 1
}

# The feature's devcontainer-feature.json, as the CLI copied it into the
# workspace.
feature_json() {
    printf '%s' "$(dirname "$0")/.devcontainer/cli-opencode/devcontainer-feature.json"
}

_opencode_is_local_bin() {
    [ "$(command -v opencode)" = /usr/local/bin/opencode ]
}

_opencode_mode_owner() {
    [ "$(stat -c '%a %u' /usr/local/bin/opencode)" = "755 0" ]
}

_opencode_reports() {
    local out
    out="$(opencode --version)"
    echo "opencode --version: ${out}"
    [ "$out" = "$1" ]
}

# expect_installed <version>: opencode is /usr/local/bin/opencode,
# root-owned, mode 0755, and reports <version>.
expect_installed() {
    if [ -z "$1" ]; then
        echo "expect_installed: no expected version" >&2
        return 1
    fi
    check "opencode resolves to /usr/local/bin/opencode" _opencode_is_local_bin
    check "opencode is mode 0755, owned by root" _opencode_mode_owner
    check "opencode --version reports $1" _opencode_reports "$1"
}
