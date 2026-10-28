#!/usr/bin/env bash
# PGDG's archive suite: the pin 18.0, which PGDG's main suite no longer
# carries, comes from a pins file at the path the pins_file option names.
# Then 17.6, which the archive carries twice (17.6-1 and 17.6-2), installs
# its highest revision through install.sh.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=postgres-client-checks.sh
source "$(dirname "$0")/postgres-client-checks.sh"

version="$(pins_version /opt/pins/postgres.env)"
check "the pins file pins 18.0" test "$version" = 18.0
expect_installed "$version"

install_sh="$(cd "$(dirname "$0")" && pwd)/.devcontainer/cli-postgres-client/install.sh"

# 17.6-2 is the highest of PGDG's 17.6 revisions on every release this
# collection supports (Debian 13, Ubuntu 24.04), so the pin 17.6 gives
# 17.6-2.*. postgresql-client-18 is removed first: psql is a wrapper that
# runs the newest installed major, and install.sh checks it reports 17.6.
highest_revision_installed() {
    as_root apt-get purge -y -q postgresql-client-18 >/dev/null || return 1
    as_root env VERSION=17.6 bash "$install_sh" || return 1
    _pkg_version_is postgresql-client-17 17.6 || return 1
    case "$(dpkg-query -W -f='${Version}' postgresql-client-17)" in
        17.6-2.*) return 0 ;;
    esac
    return 1
}
check "17.6, rebuilt in the archive, installs its highest revision (17.6-2)" highest_revision_installed
check "psql reports 17.6" _tool_reports psql 17.6

reportResults
