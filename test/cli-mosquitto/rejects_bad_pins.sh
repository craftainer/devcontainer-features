#!/usr/bin/env bash
# Negative cases. The scenario installs this distro's pin from a pins file
# at a non-default path, named by the pins_file option; this script checks
# it, purges the clients, then runs the feature's install.sh again with bad
# inputs. Each run must fail with the expected message and leave
# mosquitto-clients uninstalled. On Debian a wrong repo.mosquitto.org key
# fingerprint and an unserved release codename are checked too; on both
# distros an unsupported distribution. The good pin is reinstalled at the
# end. An expected failure can't be a scenario of its own, because a failed
# install fails the whole run
# (docs/adrs/0002-resolve-pins-from-option-env-or-pins-file-with-no-defaults.md).
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=mosquitto-checks.sh
source "$(dirname "$0")/mosquitto-checks.sh"

pins=/opt/pins/mosquitto.env
version="$(pins_version "$pins")"
distro="$(os_id)"
check "the pins_file option's file holds this distro's pin" test -n "$version"
check "the default pins file is absent" test ! -e /etc/devcontainer-features/pins.env
expect_installed "$version"

purge_clients
check "mosquitto-clients is not installed before the negative cases" clients_absent

# expect_rejected <ERE> [VAR=value...]: runs install.sh as root in a clean
# environment with only the given variables, and succeeds when it fails,
# its output matches <ERE> and mosquitto-clients didn't get installed.
expect_rejected() {
    local pattern="$1"
    shift
    run_expect_failure "$pattern" run_install "$@" || return 1
    if clients_installed; then
        echo "install.sh installed mosquitto-clients" >&2
        return 1
    fi
}

v_re="${version//./\\.}"
case "$distro" in
    debian) revision="-0mosquitto1~trixie1" ;;
    *) revision="-1build3" ;;
esac

check "no version anywhere fails, naming all three channels" expect_rejected \
    'no version for CLI_MOSQUITTO: set the version feature option, or CLI_MOSQUITTO_VERSION in the image environment, or in the pins file /etc/devcontainer-features/pins\.env \(not found\)'
check "a version this distro doesn't have fails, listing what's available" expect_rejected \
    "no mosquitto-clients 2\\.0\\.99-<revision> in the configured apt sources; available: .*${v_re}-" \
    VERSION=2.0.99
check "a leading v fails" expect_rejected \
    "version 'v${v_re}' is not an upstream version" \
    VERSION="v${version}"
check "a Debian revision fails" expect_rejected \
    "version '${v_re}${revision}' is not an upstream version" \
    VERSION="${version}${revision}"
check "a malformed CLI_MOSQUITTO_VERSION fails" expect_rejected \
    "CLI_MOSQUITTO_VERSION '2\\.0\\.' is not an upstream version" \
    CLI_MOSQUITTO_VERSION=2.0.

# with_os_release <sed expression> <command...>: runs the command with
# /etc/os-release edited by <sed expression>, then restores the original (a
# symlink to ../usr/lib/os-release, copied as the link itself).
with_os_release() {
    local expr="$1" saved result=0
    shift
    saved="$(mktemp -d)" || return 1
    as_root cp -a /etc/os-release "${saved}/os-release" || return 1
    if ! sed "$expr" /etc/os-release >"${saved}/edited" \
        || ! as_root rm -f /etc/os-release \
        || ! as_root cp "${saved}/edited" /etc/os-release; then
        result=1
    fi
    if [ "$result" -eq 0 ]; then
        "$@" || result=1
    fi
    as_root rm -f /etc/os-release
    as_root cp -a "${saved}/os-release" /etc/os-release || result=1
    as_root rm -rf "$saved"
    return "$result"
}

check "an unsupported distribution fails" with_os_release 's/^ID=.*/ID=fedora/' \
    expect_rejected "unsupported distribution ID='fedora'" VERSION="$version"

if [ "$distro" = debian ]; then
    # A wrong fingerprint: il_apt_add_repo itself, under a name of its own,
    # so the feature's mosquitto files are untouched. No keyring or list is
    # left.
    wrong_fingerprint_rejected() {
        local name=mosquitto-wrongfpr codename
        # shellcheck source=/dev/null
        codename="$(. /etc/os-release && echo "$VERSION_CODENAME")"
        run_expect_failure \
            "has fingerprint '8277CCB49EC5B595F2D2C71361611AE430993623 ?', expected 0{40}; not adding the repository" \
            as_root env -i PATH="$clean_path" bash "${test_dir}/add-repo.sh" \
            "${feature_dir}/install-lib.sh" "$name" \
            https://repo.mosquitto.org/debian/mosquitto-repo.gpg "$(printf '%040d' 0)" \
            "https://repo.mosquitto.org/debian ${codename} main" \
            || return 1
        if [ -e "/etc/apt/keyrings/${name}.gpg" ] || [ -e "/etc/apt/sources.list.d/${name}.list" ]; then
            echo "a keyring or list for ${name} was left behind" >&2
            return 1
        fi
    }
    check "a wrong repo.mosquitto.org key fingerprint fails, leaving no keyring or list" \
        wrong_fingerprint_rejected

    # An unserved codename fails with the hint, and il_apt_add_repo removes
    # the list it wrote.
    unserved_codename_rejected() {
        expect_rejected "repo.mosquitto.org doesn't build for nosuchrelease" VERSION="$version" || return 1
        if [ -e /etc/apt/sources.list.d/mosquitto.list ]; then
            echo "the nosuchrelease list was left behind" >&2
            return 1
        fi
    }
    check "a release repo.mosquitto.org doesn't build for fails" with_os_release \
        's/^VERSION_CODENAME=.*/VERSION_CODENAME=nosuchrelease/' unserved_codename_rejected
else
    echo "Skipped on ${distro}: the repo.mosquitto.org fingerprint and codename cases (Debian only)."
fi

check "the good pin installs again" run_install VERSION="$version"
expect_installed "$version"

reportResults
