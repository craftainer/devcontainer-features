#!/usr/bin/env bash
# Installs the PostgreSQL client (psql, pg_dump, pg_restore, ...) from the
# PostgreSQL Global Development Group's apt repository (PGDG) at an exact
# upstream version, e.g. 18.6. The version comes from the feature options,
# the image environment (CLI_POSTGRES_CLIENT_VERSION) or the pins file;
# there is no sha: apt checks every package against PGDG's signed
# repository, and PGDG's signing key is pinned below by fingerprint. See
# NOTES.md and
# docs/adrs/0003-pin-apt-installed-clis-by-upstream-version-with-a-verified-repo-key.md.
set -euo pipefail
# shellcheck source=install-lib.sh
. "$(dirname "$0")/install-lib.sh"

# PGDG's signing key, https://www.postgresql.org/download/linux/debian/.
PGDG_KEY_URL=https://www.postgresql.org/media/keys/ACCC4CF8.asc
PGDG_FINGERPRINT=B97B0AFCAA1A47F044F244A07FCC7D46ACCC4CF8

il_require_root
il_resolve_version CLI_POSTGRES_CLIENT

# The package is named after the major version: postgresql-client-18 for
# 18.6. Before PostgreSQL 10 the major had two parts (9.6.24 -> 9.6).
first="${IL_VERSION%%.*}"
major="$first"
if [ "$first" -lt 10 ] && [ "$IL_VERSION" != "$first" ]; then
    rest="${IL_VERSION#*.}"
    major="${first}.${rest%%.*}"
fi
pkg="postgresql-client-${major}"

# Read in a subshell: sourcing /etc/os-release here would set VERSION,
# which is the version option's variable (see il_resolve_version).
codename="$(. /etc/os-release && echo "${VERSION_CODENAME:-}")"
if ! [[ "$codename" =~ ^[a-z]+$ ]]; then
    echo "cli-postgres-client: cannot read a release codename from /etc/os-release" \
        "(VERSION_CODENAME='${codename}'); PGDG's suites are named after it" >&2
    exit 1
fi

# add_pgdg <name> <source_line>: adds a PGDG suite. il_apt_add_repo exits
# on failure, so it runs in a subshell to name the likely cause here.
add_pgdg() {
    if ! (il_apt_add_repo "$1" "$PGDG_KEY_URL" "$PGDG_FINGERPRINT" "$2"); then
        echo "cli-postgres-client: cannot add PGDG's '${2}' for this release" \
            "(${codename}). If the error above is about the suite, PGDG doesn't" \
            "build for ${codename}; supported releases are listed at" \
            "https://apt.postgresql.org/pub/repos/apt/dists/" >&2
        exit 1
    fi
}

# PGDG's main suite keeps only the latest few versions of each major; its
# archive suite keeps every version (and every rebuild), so a pin keeps
# working after the main suite moves on. Both are signed by the same key.
# When both carry a version, il_apt_install_pinned installs its highest
# Debian revision.
add_pgdg pgdg "https://apt.postgresql.org/pub/repos/apt ${codename}-pgdg main"
add_pgdg pgdg-archive "https://apt-archive.postgresql.org/pub/repos/apt ${codename}-pgdg-archive main"
il_apt_install_pinned "$pkg" "$IL_VERSION"

# psql, pg_dump and pg_restore are postgresql-client-common's pg_wrapper,
# which runs the newest installed client major unless told otherwise; check
# that it runs the one just installed. Separate assignments, so a tool that
# can't start fails the install under set -e.
for tool in psql pg_dump pg_restore; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "cli-postgres-client: ${tool} is not on PATH after installing ${pkg}" >&2
        exit 1
    fi
    out="$("$tool" --version)"
    case "$out" in
        "${tool} (PostgreSQL) ${IL_VERSION}" | "${tool} (PostgreSQL) ${IL_VERSION} "*) ;;
        *)
            echo "cli-postgres-client: ${tool} --version reports '${out}', not ${IL_VERSION}" \
                "(is a newer PostgreSQL client major installed too?)" >&2
            exit 1
            ;;
    esac
done
echo "cli-postgres-client: installed ${pkg} $(dpkg-query -W -f='${Version}' "$pkg"): ${out}"
