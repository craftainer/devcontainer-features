#!/usr/bin/env bash
# Negative cases. The scenario installs a good pin first; this script checks
# it, moves the installed valkey-cli aside, then runs the feature's
# install.sh again with bad inputs. Each run must fail with the expected
# message, leave no file behind in its TMPDIR, install no valkey-cli and
# leave /usr/local/bin as it was. The binary is put back at the end. An
# expected failure can't be a scenario of its own, because a failed install
# fails the whole run
# (docs/adrs/0002-resolve-pins-from-option-env-or-pins-file-with-no-defaults.md).
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=valkey-checks.sh
source "$(dirname "$0")/valkey-checks.sh"

version="$(scenario_version rejects_bad_pins)"
expect_installed "$version"

# The CLI copies the feature into the workspace's .devcontainer/ folder.
install_sh="$(cd "$(dirname "$0")" && pwd)/.devcontainer/cli-valkey/install.sh"
zeros="$(printf '%064d' 0)"
bad_pins="$(mktemp)"
printf 'CLI_VALKEY_VERSION=%s\n' "$version" >"$bad_pins"
chmod 0644 "$bad_pins"

as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

# Move the good install aside, so "nothing was installed" is a plain
# absence check.
aside="$(mktemp -d)"
as_root mv /usr/local/bin/valkey-cli "${aside}/valkey-cli"
bin_listing="$(ls -A /usr/local/bin)"

# expect_rejected <ERE> [VAR=value...]: runs install.sh as root in a clean
# environment with only the given variables, and succeeds when it fails,
# its output matches <ERE>, its TMPDIR is left empty, no valkey-cli was
# installed and /usr/local/bin lists the same files as before.
expect_rejected() {
    local scratch result=0
    scratch="$(mktemp -d)" || return 1
    _expect_rejected_in "$scratch" "$@" || result=$?
    as_root rm -rf "$scratch"
    as_root rm -f /usr/local/bin/valkey-cli
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
    if [ -e /usr/local/bin/valkey-cli ]; then
        echo "install.sh installed /usr/local/bin/valkey-cli" >&2
        return 1
    fi
    if [ "$(ls -A /usr/local/bin)" != "$bin_listing" ]; then
        echo "install.sh changed /usr/local/bin:" >&2
        ls -A /usr/local/bin >&2
        return 1
    fi
}

check "no pin anywhere fails, naming all three channels" expect_rejected \
    'no pin for CLI_VALKEY: set the version and sha256_(amd64|arm64) feature options, or CLI_VALKEY_VERSION and CLI_VALKEY_SHA256_(AMD64|ARM64) in the image environment, or in the pins file /etc/devcontainer-features/pins.env'
check "a version option without its sha fails" expect_rejected \
    'the feature options set version but not sha256_(amd64|arm64)' \
    VERSION="$version"
check "sha options without the version fail" expect_rejected \
    'the feature options set sha256_(amd64|arm64) but not version' \
    SHA256_AMD64="$zeros" SHA256_ARM64="$zeros"
case "$(uname -m)" in
    x86_64) other_arch=ARM64 ;;
    *) other_arch=AMD64 ;;
esac
check "only the other arch's sha option fails, without falling through" expect_rejected \
    'the feature options set sha256_(amd64|arm64) but not version or sha256_(amd64|arm64) \(this machine is (amd64|arm64)\)' \
    "SHA256_${other_arch}=${zeros}" CLI_VALKEY_VERSION="$version" \
    "CLI_VALKEY_SHA256_AMD64=${zeros}" "CLI_VALKEY_SHA256_ARM64=${zeros}"
check "an image environment version without its sha fails" expect_rejected \
    'the image environment set CLI_VALKEY_VERSION but not CLI_VALKEY_SHA256_(AMD64|ARM64)' \
    CLI_VALKEY_VERSION="$version"
check "a pins file version without its sha fails" expect_rejected \
    "the pins file ${bad_pins} set CLI_VALKEY_VERSION but not CLI_VALKEY_SHA256_(AMD64|ARM64)" \
    PINS_FILE="$bad_pins"
check "a malformed sha fails" expect_rejected \
    'sha256_(amd64|arm64) .not-a-sha. is not a sha256' \
    VERSION="$version" SHA256_AMD64=not-a-sha SHA256_ARM64=not-a-sha
check "a version with a leading v fails" expect_rejected \
    "version 'v${version}' must not start with v" \
    VERSION="v${version}" SHA256_AMD64="$zeros" SHA256_ARM64="$zeros"
# The empty-TMPDIR check here covers install.sh's EXIT trap as a whole;
# fetch_mismatch_deletes_dest below checks il_fetch_verified's own delete.
check "a wrong sha fails and leaves nothing in TMPDIR" expect_rejected \
    'sha256 mismatch for https://download.valkey.io/releases/' \
    VERSION="$version" SHA256_AMD64="$zeros" SHA256_ARM64="$zeros"

# fetch_mismatch_deletes_dest: il_fetch_verified, called outside any trap,
# fails with a sha mismatch (not some other error) and deletes <dest> itself.
fetch_mismatch_deletes_dest() {
    local dir dest asset_arch out status=0 result=0
    case "$(uname -m)" in
        x86_64) asset_arch=x86_64 ;;
        *) asset_arch=arm64 ;;
    esac
    dir="$(mktemp -d)" || return 1
    dest="${dir}/valkey.tar.gz"
    out="$(bash -c '. "$1" && il_fetch_verified "$2" "$3" "$4"' _ \
        "$(dirname "$install_sh")/install-lib.sh" \
        "https://download.valkey.io/releases/valkey-${version}-noble-${asset_arch}.tar.gz" \
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

as_root mv "${aside}/valkey-cli" /usr/local/bin/valkey-cli
rm -rf "$aside" "$bad_pins"
check "the good install is back in place" _valkey_cli_reports "$version"

reportResults
