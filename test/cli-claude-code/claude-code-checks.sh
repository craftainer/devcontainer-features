# shellcheck shell=bash
# Checks shared by the cli-claude-code scenario scripts. The CLI copies this
# test folder into the test container's workspace, next to the scenario
# scripts and scenarios.json. Source it after dev-container-features-test-lib.
# Nothing here runs claude against the network: --version only.

# Prints the "version" option of scenario <name> in scenarios.json.
scenario_version() {
    awk -v name="\"$1\":" '
        $1 == name { inside = 1; next }
        inside && /"version":/ { gsub(/[",]/, "", $2); print $2; exit }
    ' "$(dirname "$0")/scenarios.json"
}

# Prints CLI_CLAUDE_CODE_VERSION from the pins file <file>.
pins_version() {
    sed -nE 's/^[[:blank:]]*(export[[:blank:]]+)?CLI_CLAUDE_CODE_VERSION=["'\'']?([^"'\''[:blank:]#]+).*/\2/p' "$1" | tail -n 1
}

# The feature's devcontainer-feature.json, as the CLI copied it into the
# workspace.
feature_json() {
    printf '%s' "$(dirname "$0")/.devcontainer/cli-claude-code/devcontainer-feature.json"
}

_claude_is_local_bin() {
    [ "$(command -v claude)" = /usr/local/bin/claude ]
}

_claude_mode_owner() {
    [ "$(stat -c '%a %u' /usr/local/bin/claude)" = "755 0" ]
}

_claude_reports() {
    local out
    out="$(claude --version)"
    echo "claude --version: ${out}"
    [ "$out" = "$1 (Claude Code)" ]
}

# expect_installed <version>: claude is /usr/local/bin/claude, root-owned,
# mode 0755, and reports <version>.
expect_installed() {
    if [ -z "$1" ]; then
        echo "expect_installed: no expected version" >&2
        return 1
    fi
    check "claude resolves to /usr/local/bin/claude" _claude_is_local_bin
    check "claude is mode 0755, owned by root" _claude_mode_owner
    check "claude --version reports $1" _claude_reports "$1"
}
