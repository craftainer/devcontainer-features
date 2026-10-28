#!/usr/bin/env bash
# Negative cases. The scenario installs a good pin first; this script then
# runs the feature's install.sh again with bad inputs and checks that each
# run fails with the expected message, leaves no file behind in its TMPDIR
# and doesn't touch the installed s5cmd. An expected failure can't be a
# scenario of its own, because a failed install fails the whole run
# (docs/adrs/0002-resolve-pins-from-option-env-or-pins-file-with-no-defaults.md).
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=s5cmd-checks.sh
source "$(dirname "$0")/s5cmd-checks.sh"

expect_installed "$(scenario_version rejects_bad_pins)"

# The CLI copies the feature into the workspace's .devcontainer/ folder.
install_sh="$(cd "$(dirname "$0")" && pwd)/.devcontainer/cli-s5cmd/install.sh"
installed_sha="$(sha256sum /usr/local/bin/s5cmd)"
installed_version="$(s5cmd version | sed -E 's/^v([^-]+).*/\1/')"
zeros="$(printf '%064d' 0)"
bad_pins="$(mktemp)"
printf 'CLI_S5CMD_VERSION=%s\n' "$installed_version" >"$bad_pins"
chmod 0644 "$bad_pins"

as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

# expect_rejected <ERE> [VAR=value...]: runs install.sh as root in a clean
# environment with only the given variables, and succeeds when it fails,
# its output matches <ERE>, its TMPDIR is left empty and the installed
# s5cmd is unchanged.
expect_rejected() {
    local scratch result=0
    scratch="$(mktemp -d)" || return 1
    _expect_rejected_in "$scratch" "$@" || result=$?
    as_root rm -rf "$scratch"
    return "$result"
}

_expect_rejected_in() {
    local scratch="$1" pattern="$2" out status=0
    shift 2
    out="$(as_root env -i PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
        TMPDIR="$scratch" "$@" bash "$install_sh" 2>&1)" || status=$?
    printf '%s\n' "$out"
    if [ "$status" -eq 0 ]; then
        echo "install.sh succeeded; expected a failure" >&2
        return 1
    fi
    if ! printf '%s\n' "$out" | grep -Eq -- "$pattern"; then
        echo "install.sh output doesn't match: ${pattern}" >&2
        return 1
    fi
    if [ -n "$(as_root find "$scratch" -mindepth 1 -print -quit)" ]; then
        echo "install.sh left files in its TMPDIR:" >&2
        as_root find "$scratch" -mindepth 1 >&2
        return 1
    fi
    if [ "$(sha256sum /usr/local/bin/s5cmd)" != "$installed_sha" ]; then
        echo "install.sh changed /usr/local/bin/s5cmd" >&2
        return 1
    fi
}

check "no pin anywhere fails, naming all three channels" expect_rejected \
    'no pin for CLI_S5CMD: set the version and sha256_(amd64|arm64) feature options, or CLI_S5CMD_VERSION and CLI_S5CMD_SHA256_(AMD64|ARM64) in the image environment, or in the pins file /etc/devcontainer-features/pins.env'
check "a version option without its sha fails" expect_rejected \
    'the feature options set version but not sha256_(amd64|arm64)' \
    VERSION="$installed_version"
check "sha options without the version fail" expect_rejected \
    'the feature options set sha256_(amd64|arm64) but not version' \
    SHA256_AMD64="$zeros" SHA256_ARM64="$zeros"
case "$(uname -m)" in
    x86_64) other_arch=ARM64 ;;
    *) other_arch=AMD64 ;;
esac
check "only the other arch's sha option fails, without falling through" expect_rejected \
    'the feature options set sha256_(amd64|arm64) but not version or sha256_(amd64|arm64) \(this machine is (amd64|arm64)\)' \
    "SHA256_${other_arch}=${zeros}" CLI_S5CMD_VERSION="$installed_version" \
    "CLI_S5CMD_SHA256_AMD64=${zeros}" "CLI_S5CMD_SHA256_ARM64=${zeros}"
check "an image environment version without its sha fails" expect_rejected \
    'the image environment set CLI_S5CMD_VERSION but not CLI_S5CMD_SHA256_(AMD64|ARM64)' \
    CLI_S5CMD_VERSION="$installed_version"
check "a pins file version without its sha fails" expect_rejected \
    "the pins file ${bad_pins} set CLI_S5CMD_VERSION but not CLI_S5CMD_SHA256_(AMD64|ARM64)" \
    PINS_FILE="$bad_pins"
check "a malformed sha fails" expect_rejected \
    'sha256_(amd64|arm64) .not-a-sha. is not a sha256' \
    VERSION="$installed_version" SHA256_AMD64=not-a-sha SHA256_ARM64=not-a-sha
# The empty-TMPDIR check here covers install.sh's EXIT trap as a whole;
# fetch_mismatch_deletes_dest below checks il_fetch_verified's own delete.
check "a wrong sha fails and leaves nothing in TMPDIR" expect_rejected \
    'sha256 mismatch for https://github.com/peak/s5cmd/releases/download/' \
    VERSION="$installed_version" SHA256_AMD64="$zeros" SHA256_ARM64="$zeros"

# fetch_mismatch_deletes_dest: il_fetch_verified, called outside any trap,
# fails with a sha mismatch (not some other error) and deletes <dest> itself.
fetch_mismatch_deletes_dest() {
    local dir dest asset_arch out status=0 result=0
    case "$(uname -m)" in
        x86_64) asset_arch=64bit ;;
        *) asset_arch=arm64 ;;
    esac
    dir="$(mktemp -d)" || return 1
    dest="${dir}/s5cmd.tar.gz"
    out="$(bash -c '. "$1" && il_fetch_verified "$2" "$3" "$4"' _ \
        "$(dirname "$install_sh")/install-lib.sh" \
        "https://github.com/peak/s5cmd/releases/download/v${installed_version}/s5cmd_${installed_version}_Linux-${asset_arch}.tar.gz" \
        "$zeros" "$dest" 2>&1)" || status=$?
    printf '%s\n' "$out"
    if [ "$status" -eq 0 ]; then
        echo "il_fetch_verified succeeded; expected a sha mismatch" >&2
        result=1
    elif ! printf '%s\n' "$out" | grep -q 'sha256 mismatch for '; then
        echo "il_fetch_verified failed, but not with a sha mismatch" >&2
        result=1
    elif [ -e "$dest" ]; then
        echo "il_fetch_verified left ${dest} behind after a mismatch" >&2
        result=1
    fi
    rm -rf "$dir"
    return "$result"
}
check "il_fetch_verified deletes its download on a sha mismatch" fetch_mismatch_deletes_dest
check "a version with a leading v fails" expect_rejected \
    "version 'v${installed_version}' must not start with v" \
    VERSION="v${installed_version}" SHA256_AMD64="$zeros" SHA256_ARM64="$zeros"

rm -f "$bad_pins"

reportResults
