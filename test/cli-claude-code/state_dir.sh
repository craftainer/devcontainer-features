#!/usr/bin/env bash
# The state directory: install.sh creates ~/.claude for the remote user,
# mode 0700, so a named volume mounted there later is seeded writable.
# state_dir/Dockerfile pre-creates it root-owned with mode 0755, so this
# also checks that an existing directory is handed over. The remote user is
# vscode on the devcontainers base images and root on bare debian/ubuntu.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=claude-code-checks.sh
source "$(dirname "$0")/claude-code-checks.sh"

if [ -d /home/vscode ]; then
    remote_user=vscode
else
    remote_user=root
fi
remote_home="$(getent passwd "$remote_user" | cut -d: -f6)"
echo "remote user: ${remote_user}, home: ${remote_home}, running as: $(id -un)"

_state_dir_is_dir() {
    [ -d "${remote_home}/.claude" ] && [ ! -L "${remote_home}/.claude" ]
}

_state_dir_owner_mode() {
    local got
    got="$(stat -c '%U:%G %a' "${remote_home}/.claude")"
    echo "${remote_home}/.claude: ${got}"
    [ "$got" = "${remote_user}:$(id -gn "$remote_user") 700" ]
}

_state_dir_writable_by_user() {
    local probe="${remote_home}/.claude/.write-probe"
    if [ "$(id -un)" = "$remote_user" ]; then
        touch "$probe" && rm -f "$probe"
    else
        sudo -u "$remote_user" sh -c 'touch "$1" && rm -f "$1"' _ "$probe"
    fi
}

expect_installed "$(scenario_version state_dir)"
check "the tests run as the remote user" test "$(id -un)" = "$remote_user"
check "${remote_home}/.claude is a directory, not a symlink" _state_dir_is_dir
check "${remote_home}/.claude is owned by ${remote_user} with mode 0700" _state_dir_owner_mode
check "${remote_user} can write to ${remote_home}/.claude" _state_dir_writable_by_user

reportResults
