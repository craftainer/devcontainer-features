#!/usr/bin/env bash
# The state directories: install.sh creates ~/.config/opencode and
# ~/.local/share/opencode (where auth.json lives) for the remote user, mode
# 0700, so named volumes mounted there later are seeded writable.
# state_dir/Dockerfile pre-creates both root-owned with mode 0755, so this
# also checks that existing directories are handed over. The remote user is
# vscode on the devcontainers base images and root on bare debian/ubuntu.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=opencode-checks.sh
source "$(dirname "$0")/opencode-checks.sh"

if [ -d /home/vscode ]; then
    remote_user=vscode
else
    remote_user=root
fi
remote_home="$(getent passwd "$remote_user" | cut -d: -f6)"
echo "remote user: ${remote_user}, home: ${remote_home}, running as: $(id -un)"

_state_dir_is_dir() {
    [ -d "$1" ] && [ ! -L "$1" ]
}

_state_dir_owner_mode() {
    local got
    got="$(stat -c '%U:%G %a' "$1")"
    echo "$1: ${got}"
    [ "$got" = "${remote_user}:$(id -gn "$remote_user") 700" ]
}

_state_dir_writable_by_user() {
    local probe="$1/.write-probe"
    if [ "$(id -un)" = "$remote_user" ]; then
        touch "$probe" && rm -f "$probe"
    else
        sudo -u "$remote_user" sh -c 'touch "$1" && rm -f "$1"' _ "$probe"
    fi
}

# The directories are checked before opencode first runs below, so what is
# checked is what install.sh left in the image.
check "the tests run as the remote user" test "$(id -un)" = "$remote_user"
for dir in "${remote_home}/.config/opencode" "${remote_home}/.local/share/opencode"; do
    check "${dir} is a directory, not a symlink" _state_dir_is_dir "$dir"
    check "${dir} is owned by ${remote_user} with mode 0700" _state_dir_owner_mode "$dir"
    check "${remote_user} can write to ${dir}" _state_dir_writable_by_user "$dir"
done
expect_installed "$(scenario_version state_dir)"

reportResults
