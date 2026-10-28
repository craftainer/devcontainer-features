#!/usr/bin/env bash
# Negative cases. The scenario installs a good pin first; this script checks
# it, purges the installed client, then runs the feature's install.sh again
# with bad inputs. Each run must fail with the expected message and leave no
# postgresql-client-<major> package installed. A wrong PGDG key fingerprint
# and an unserved release codename are checked too. The good pin is
# reinstalled at the end. An expected failure can't be a scenario of its
# own, because a failed install fails the whole run
# (docs/adrs/0002-resolve-pins-from-option-env-or-pins-file-with-no-defaults.md).
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=postgres-client-checks.sh
source "$(dirname "$0")/postgres-client-checks.sh"

version="$(scenario_version rejects_bad_pins)"
expect_installed "$version"

# The CLI copies the feature into the workspace's .devcontainer/ folder.
test_dir="$(cd "$(dirname "$0")" && pwd)"
feature_dir="${test_dir}/.devcontainer/cli-postgres-client"
install_sh="${feature_dir}/install.sh"
clean_path=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
# shellcheck source=/dev/null
codename="$(. /etc/os-release && echo "$VERSION_CODENAME")"

# Prints the postgresql-client-<major> packages dpkg has installed.
installed_clients() {
    dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' 'postgresql-client-*' 2>/dev/null \
        | awk '$1 == "ii" && $2 ~ /^postgresql-client-[0-9]/ { print $2 }'
}

as_root apt-get purge -y -q "$(client_pkg "$version")" >/dev/null
check "no postgresql-client-<major> is installed before the negative cases" \
    test -z "$(installed_clients)"

# run_expect_failure <ERE> <command...>: succeeds when the command fails
# and its output matches <ERE>.
run_expect_failure() {
    local pattern="$1" out status=0
    shift
    out="$("$@" 2>&1)" || status=$?
    printf '%s\n' "$out" | tail -n 5
    if [ "$status" -eq 0 ]; then
        echo "succeeded; expected a failure" >&2
        return 1
    fi
    if ! printf '%s\n' "$out" | grep -Eq -- "$pattern"; then
        echo "output doesn't match: ${pattern}" >&2
        return 1
    fi
}

# expect_rejected <ERE> [VAR=value...]: runs install.sh as root in a clean
# environment with only the given variables, and succeeds when it fails,
# its output matches <ERE> and no postgresql-client-<major> got installed.
expect_rejected() {
    local pattern="$1"
    shift
    run_expect_failure "$pattern" as_root env -i PATH="$clean_path" "$@" bash "$install_sh" || return 1
    if [ -n "$(installed_clients)" ]; then
        echo "install.sh installed: $(installed_clients)" >&2
        return 1
    fi
}

check "no version anywhere fails, naming all three channels" expect_rejected \
    'no version for CLI_POSTGRES_CLIENT: set the version feature option, or CLI_POSTGRES_CLIENT_VERSION in the image environment, or in the pins file /etc/devcontainer-features/pins.env \(not found\)'
check "a version PGDG doesn't have fails, listing what's available" expect_rejected \
    "no postgresql-client-18 18\\.99-<revision> in the configured apt sources; available: .*${version//./\\.}-" \
    VERSION=18.99
check "a leading v fails" expect_rejected \
    "version 'v${version}' is not an upstream version" \
    VERSION="v${version}"
check "a Debian revision fails" expect_rejected \
    "version '${version}-1\\.pgdg13\\+2' is not an upstream version" \
    VERSION="${version}-1.pgdg13+2"
check "a trailing dot fails" expect_rejected \
    "CLI_POSTGRES_CLIENT_VERSION '18\\.' is not an upstream version" \
    CLI_POSTGRES_CLIENT_VERSION=18.

# A wrong fingerprint: il_apt_add_repo itself, under a name of its own, so
# the feature's pgdg files are untouched. No keyring or list is left.
wrong_fingerprint_rejected() {
    local name=pgdg-wrongfpr
    run_expect_failure \
        "has fingerprint 'B97B0AFCAA1A47F044F244A07FCC7D46ACCC4CF8 ?', expected 0{40}; not adding the repository" \
        as_root env -i PATH="$clean_path" bash "${test_dir}/add-repo.sh" \
        "${feature_dir}/install-lib.sh" "$name" \
        https://www.postgresql.org/media/keys/ACCC4CF8.asc "$(printf '%040d' 0)" \
        "https://apt.postgresql.org/pub/repos/apt ${codename}-pgdg main" \
        || return 1
    if [ -e "/etc/apt/keyrings/${name}.gpg" ] || [ -e "/etc/apt/sources.list.d/${name}.list" ]; then
        echo "a keyring or list for ${name} was left behind" >&2
        return 1
    fi
}
check "a wrong PGDG key fingerprint fails, leaving no keyring or list" wrong_fingerprint_rejected

# An unserved codename: install.sh reads it from /etc/os-release, so a copy
# with a made-up VERSION_CODENAME is put in place and the original (a
# symlink to ../usr/lib/os-release, copied as the link itself) restored.
unserved_codename_rejected() {
    local saved result=0
    saved="$(mktemp -d)" || return 1
    as_root cp -a /etc/os-release "${saved}/os-release" || return 1
    as_root sh -c 'sed "s/^VERSION_CODENAME=.*/VERSION_CODENAME=nosuchrelease/" /etc/os-release >/etc/os-release.new && mv -f /etc/os-release.new /etc/os-release' \
        || result=1
    if [ "$result" -eq 0 ]; then
        expect_rejected "PGDG doesn't build for nosuchrelease" VERSION="$version" || result=1
    fi
    as_root rm -f /etc/os-release
    as_root cp -a "${saved}/os-release" /etc/os-release || result=1
    as_root rm -rf "$saved"
    if [ -e /etc/apt/sources.list.d/pgdg.list ] && grep -q nosuchrelease /etc/apt/sources.list.d/pgdg.list; then
        echo "the nosuchrelease list was left behind" >&2
        result=1
    fi
    return "$result"
}
check "a release PGDG doesn't build for fails" unserved_codename_rejected

check "the good pin installs again" as_root env -i PATH="$clean_path" VERSION="$version" bash "$install_sh"
check "psql reports ${version} again" _tool_reports psql "$version"

reportResults
