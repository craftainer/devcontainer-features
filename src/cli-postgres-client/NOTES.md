## What it installs

The PostgreSQL client package `postgresql-client-<major>` (e.g.
`postgresql-client-18`) from the
[PostgreSQL apt repository (PGDG)](https://wiki.postgresql.org/wiki/Apt),
at the exact upstream version you pin. That gives you `psql`, `pg_dump`,
`pg_restore`, `pg_dumpall`, `pg_isready` and the other client tools. Debian's
`postgresql-client-common` puts them on `PATH` as `/usr/bin/psql` and so on.
These are `pg_wrapper` links, which run the newest client major installed.
`libpq5` comes from PGDG as well. No server is installed.

The feature adds two PGDG suites, both signed with the same key:

- `apt.postgresql.org`, `<codename>-pgdg`: the main suite. It keeps only the
  latest few versions of each major.
- `apt-archive.postgresql.org`, `<codename>-pgdg-archive`: the archive. It
  keeps every version PGDG has published, and every rebuild. Your pin keeps
  working after the main suite has moved on.

The archive's package index is large: each install downloads about 3.6 MB
more (about 21 MB unpacked). The apt lists are deleted afterwards, so none
of it stays in the image.

After installing, the feature checks that `psql`, `pg_dump` and
`pg_restore` on `PATH` report the pinned version. If you already have a
newer client major in the image, `pg_wrapper` runs that one instead, and
the install fails.

## Pinning the version

This feature has no default version. You choose the PostgreSQL release,
and the install fails unless it finds one. Pick the one that matches your
server, e.g. `18.6` for a Postgres 18.6 server.

The version is the **upstream** version: digits and dots, e.g. `18.6`. It
has no leading `v` and no Debian revision. `v18.6`, `18.6-1.pgdg13+2` and
`18.` are rejected. The major (`18`) picks the package
(`postgresql-client-18`). The feature then installs the `18.6-<revision>`
build PGDG has for your distro, so one pin works on every distro and arch
PGDG builds for. When PGDG has several revisions of that version, the
highest Debian revision is installed. For example, the archive carries both
`17.6-1` and `17.6-2`, and the feature installs `17.6-2`. A PGDG rebuild of
your version is therefore picked up silently at the next build (see
[ADR 0003](../../docs/adrs/0003-pin-apt-installed-clis-by-upstream-version-with-a-verified-repo-key.md)).

A version PGDG doesn't have (e.g. `18.99`) fails, and the error lists the
versions available. The feature never downgrades: if the image already has
a newer build of the same package, apt refuses the install, and the
feature fails rather than forcing it.

The pin can come from three places. The feature uses the first one that
sets it.

### 1. Feature options

```jsonc
"features": {
  "ghcr.io/craftainer/devcontainer-features/cli-postgres-client:1": {
    "version": "18.6"
  }
}
```

To keep the pin out of `devcontainer.json`, feed the option from the host's
environment:

```jsonc
"ghcr.io/craftainer/devcontainer-features/cli-postgres-client:1": {
  "version": "${localEnv:CLI_POSTGRES_CLIENT_VERSION}"
}
```

### 2. An environment variable in your image

Set `CLI_POSTGRES_CLIENT_VERSION` with `ENV` in the Dockerfile your
devcontainer builds from, and leave the feature's options empty:

```dockerfile
ENV CLI_POSTGRES_CLIENT_VERSION=18.6
```

```jsonc
"build": { "dockerfile": "Dockerfile" },
"features": {
  "ghcr.io/craftainer/devcontainer-features/cli-postgres-client:1": {}
}
```

### 3. A pins file in your image

Put a `KEY=value` line in a file and `COPY` it into the image at
`/etc/devcontainer-features/pins.env`. One file can hold the pins of every
feature in this collection, and each feature reads only its own keys.

```sh
# pins.env
CLI_POSTGRES_CLIENT_VERSION=18.6
```

```dockerfile
COPY pins.env /etc/devcontainer-features/pins.env
```

The file is parsed, never sourced. The feature understands `KEY=value`
lines (optionally after `export`), `#` comments and quoted values, and
expands nothing. To keep the file somewhere else, set the `pins_file`
option to its path in the image:

```jsonc
"ghcr.io/craftainer/devcontainer-features/cli-postgres-client:1": {
  "pins_file": "/opt/pins/devcontainer.env"
}
```

## Trust model: no sha

Unlike this collection's download features, you supply no sha256 here.
PGDG builds a different `.deb` for each distro and arch, and so do its
dependencies such as `libpq5`. A sha pin would therefore need a whole set
of shas that nobody can keep current. Instead, apt checks every package
against the repository's signed index, so the thing to trust is PGDG's
signing key.

The feature pins that key by a fingerprint constant,
`B97B0AFCAA1A47F044F244A07FCC7D46ACCC4CF8`, as the official devcontainers
features do. It fetches
`https://www.postgresql.org/media/keys/ACCC4CF8.asc` over https and checks
that the exact key bytes it installs hold one primary key with that
fingerprint. Then it writes the key to `/etc/apt/keyrings/pgdg.gpg` and
`/etc/apt/keyrings/pgdg-archive.gpg`. Each `/etc/apt/sources.list.d/*.list`
entry trusts only its own key file (`signed-by`). A different key fails
the install before anything is written. If PGDG rotates its key, the
feature needs a new release. See
[ADR 0003](../../docs/adrs/0003-pin-apt-installed-clis-by-upstream-version-with-a-verified-repo-key.md).

The install installs `curl`, `ca-certificates` and `gpg` if any of them is
missing, and leaves them in the image.

## Install order with `ssl-ca`

PGDG is reached over https. Behind a TLS-intercepting proxy, your corporate
root CA must be trusted before this feature runs. This feature deliberately
declares no `installsAfter` on `ssl-ca`: the Dev Container CLI fetches every
`installsAfter` reference from ghcr.io, so declaring one would make every
build reach ghcr.io for `ssl-ca`, even when you don't use it. If you use
this collection's `ssl-ca` feature, list it first in
`overrideFeatureInstallOrder`:

```jsonc
"overrideFeatureInstallOrder": [
  "ghcr.io/craftainer/devcontainer-features/ssl-ca",
  "ghcr.io/craftainer/devcontainer-features/cli-postgres-client"
]
```

## Credentials

The feature installs only the client. It declares no mounts and stores no
state. Point the tools at your server with libpq's
[environment variables](https://www.postgresql.org/docs/current/libpq-envars.html):
`PGHOST`, `PGPORT`, `PGUSER`, `PGDATABASE`, and `PGPASSWORD` or
`PGPASSFILE`. A password file (`~/.pgpass` format, mode `0600`) keeps the
password out of the environment of every process. Pass them in from the
host instead of baking them into the image:

```jsonc
"containerEnv": {
  "PGHOST": "db",
  "PGUSER": "${localEnv:PGUSER}",
  "PGPASSWORD": "${localEnv:PGPASSWORD}"
}
```

or, with Docker Compose, from an `env_file` that stays out of version
control:

```yaml
services:
  devcontainer:
    env_file: .secrets/postgres.env
```

## OS support

Debian 13 (trixie) and Ubuntu 24.04 (noble) or later, on amd64 and arm64:
any release PGDG builds for. The suite is chosen from `VERSION_CODENAME` in
`/etc/os-release`. A release PGDG doesn't serve fails the install with a
pointer to
[PGDG's list of suites](https://apt.postgresql.org/pub/repos/apt/dists/).
