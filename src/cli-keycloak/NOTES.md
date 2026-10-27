## Two flavors, one name

The `flavor` option picks what `kcadm` is. **The two share the name
`kcadm` but not its syntax**, so a script written for one doesn't run
with the other.

| Flavor | What `kcadm` is | Needs | Pin |
| --- | --- | --- | --- |
| `official` (default) | Keycloak's own [admin CLI](https://www.keycloak.org/docs/latest/server_admin/#the-admin-cli), `kcadm.sh`, also installed as `kcadm` | Java 21 or newer (installed by default) | version and sha256 |
| `rest` | a curl wrapper around the [Admin REST API](https://www.keycloak.org/docs-api/latest/rest-api/): `kcadm METHOD PATH [JSON]` | `curl` and `python3` (installed if missing) | none |

```sh
# official
kcadm.sh config credentials --server "$KEYCLOAK_URL" --realm master --user "$KEYCLOAK_ADMIN"
kcadm.sh get realms/master/users

# rest
kcadm GET /admin/realms/master/users
```

`official` puts `kcadm.sh` and its client jars in
`/usr/local/lib/keycloak-cli`, with `kcadm` and `kcadm.sh` on `PATH`.
`rest` installs only `/usr/local/bin/kcadm`; it downloads nothing, so it
needs no version or sha256 and ignores them if they are set.

The flavor comes from the first of these that sets it: the `flavor`
option, `CLI_KEYCLOAK_FLAVOR` in the image environment, or
`CLI_KEYCLOAK_FLAVOR` in the pins file (see below). If none does, it's
`official`. Any value other than `official` or `rest` fails the install.

```jsonc
"ghcr.io/craftainer/devcontainer-features/cli-keycloak:1": {
  "flavor": "rest"
}
```

## Pinning the version (`official`)

`official` has no default version. You choose the Keycloak release and
supply the sha256 of its tarball, and the install fails unless it finds
both. The tarball is the same on every arch, so there is one `sha256`.

Upstream publishes only `.sha1`, `.md5` and `.asc` files next to
`keycloak-<version>.tar.gz` on
[github.com/keycloak/keycloak/releases](https://github.com/keycloak/keycloak/releases),
no sha256. So the sha256 is your own pin: download the tarball once,
check it against upstream's `.sha1` (or its `.asc` signature), and record
its sha256:

```sh
v=26.7.5
curl -fsSLO "https://github.com/keycloak/keycloak/releases/download/${v}/keycloak-${v}.tar.gz"
echo "$(curl -fsSL "https://github.com/keycloak/keycloak/releases/download/${v}/keycloak-${v}.tar.gz.sha1")  keycloak-${v}.tar.gz" | sha1sum -c -
sha256sum "keycloak-${v}.tar.gz"
```

The version is the release tag as it is, with no `v` (`26.7.5`). Pick
the one that matches your Keycloak server.

The pin can come from three places. The feature uses the first one that
sets either the version or the sha256, and that place must set both: a
version in one place is never paired with a sha256 from another.

### 1. Feature options

```jsonc
"features": {
  "ghcr.io/craftainer/devcontainer-features/cli-keycloak:1": {
    "version": "26.7.5",
    "sha256": "87d680d13cf4600d232ca0433a2553c57ebf03e56f7718fc0d03a1a8705497c8"
  }
}
```

To keep the pin out of `devcontainer.json`, feed the options from the
host's environment:

```jsonc
"ghcr.io/craftainer/devcontainer-features/cli-keycloak:1": {
  "version": "${localEnv:CLI_KEYCLOAK_VERSION}",
  "sha256": "${localEnv:CLI_KEYCLOAK_SHA256}"
}
```

### 2. Environment variables in your image

Set `CLI_KEYCLOAK_VERSION` and `CLI_KEYCLOAK_SHA256` (and, if you like,
`CLI_KEYCLOAK_FLAVOR`) with `ENV` in the Dockerfile your devcontainer
builds from, and leave the feature's options empty:

```dockerfile
ENV CLI_KEYCLOAK_VERSION=26.7.5
ENV CLI_KEYCLOAK_SHA256=87d680d13cf4600d232ca0433a2553c57ebf03e56f7718fc0d03a1a8705497c8
```

```jsonc
"build": { "dockerfile": "Dockerfile" },
"features": {
  "ghcr.io/craftainer/devcontainer-features/cli-keycloak:1": {}
}
```

### 3. A pins file in your image

Put the same `KEY=value` lines in a file and `COPY` it into the image at
`/etc/devcontainer-features/pins.env`. One file can hold the pins of every
feature in this collection; each feature reads only its own keys.

```sh
# pins.env
CLI_KEYCLOAK_FLAVOR=official
CLI_KEYCLOAK_VERSION=26.7.5
CLI_KEYCLOAK_SHA256=87d680d13cf4600d232ca0433a2553c57ebf03e56f7718fc0d03a1a8705497c8
```

```dockerfile
COPY pins.env /etc/devcontainer-features/pins.env
```

The file is parsed, never sourced: `KEY=value` lines (optionally after
`export`), `#` comments and quoted values are understood, and nothing is
expanded. To keep it somewhere else, set the `pins_file` option to its
path in the image:

```jsonc
"ghcr.io/craftainer/devcontainer-features/cli-keycloak:1": {
  "pins_file": "/opt/pins/devcontainer.env"
}
```

## Java (`official`)

`kcadm.sh` runs on the JVM, and Keycloak 26 needs Java 21 or newer. With
`install_jre` on (the default), the feature installs the distro's
`default-jre-headless`, which is OpenJDK 21 on Debian 13 and Ubuntu
24.04, and fails if the result is older than 21.

Set `install_jre` to `false` if your image already has Java, for example
from the official `java` feature. kcadm is then installed without
checking for Java. **Java 21 or newer must still be on `PATH` (or in
`JAVA_HOME`) when you run kcadm**; the install prints a note if none is
there yet, and a warning if it finds an older one. `install_jre` is
ignored for `rest`.

## The `rest` wrapper

`kcadm METHOD PATH [JSON]` fetches an admin token for the `admin-cli`
client in the `master` realm, sends one request to `$KEYCLOAK_URL$PATH`
with it, and pretty-prints the JSON reply. It reads at run time:

| Variable | Meaning |
| --- | --- |
| `KEYCLOAK_URL` | the server's base URL; default `http://keycloak:8080` |
| `KEYCLOAK_ADMIN` | the admin user name (required) |
| `KEYCLOAK_ADMIN_PASSWORD` | its password (required) |

```sh
kcadm GET /admin/realms
kcadm POST /admin/realms/myrealm/users '{"username": "alice", "enabled": true}'
```

It exits non-zero on a failed login or an HTTP error. curl runs with
`-sf`, so the HTTP status and body of an error aren't shown. It is the craftainer app templates' `develop.d` wrapper,
ported as it is, so its usage example names `template-fastapi`'s realm.

## Install order with `ssl-ca`

If you also use this collection's `ssl-ca` feature for a corporate root
CA, the CA has to be trusted before the Keycloak tarball is downloaded.
Installed first, it is also in the system trust store when
`default-jre-headless` is installed, which builds the JRE's `cacerts`
from that store (Debian's `ca-certificates-java`). This feature deliberately declares no `installsAfter` on
`ssl-ca`: the Dev Container CLI fetches every `installsAfter` reference
from ghcr.io, so declaring one would make every build reach ghcr.io for
`ssl-ca` even when you don't use it. If you use `ssl-ca`, list it first in
`overrideFeatureInstallOrder`:

```jsonc
"overrideFeatureInstallOrder": [
  "ghcr.io/craftainer/devcontainer-features/ssl-ca",
  "ghcr.io/craftainer/devcontainer-features/cli-keycloak"
]
```

## Credentials

The feature installs only the CLI: it declares no mounts and stores no
state. Keep the admin credentials in `KEYCLOAK_*` environment variables
and pass them in from the host instead of baking them into the image:

```jsonc
"containerEnv": {
  "KEYCLOAK_URL": "${localEnv:KEYCLOAK_URL}",
  "KEYCLOAK_ADMIN": "${localEnv:KEYCLOAK_ADMIN}",
  "KEYCLOAK_ADMIN_PASSWORD": "${localEnv:KEYCLOAK_ADMIN_PASSWORD}"
}
```

or, with Docker Compose, from an `env_file` that stays out of version
control:

```yaml
services:
  devcontainer:
    env_file: .secrets/keycloak.env
```

`rest` reads them itself. `official`'s `kcadm.sh` doesn't: pass them to
`config credentials`, which keeps its session token in
`~/.keycloak/kcadm.config` (gone after a rebuild, so log in again).
`kcadm.sh` takes the password from `KC_CLI_PASSWORD` when `--password` is
not given, which keeps it off the command line:

```sh
KC_CLI_PASSWORD="$KEYCLOAK_ADMIN_PASSWORD" \
  kcadm.sh config credentials --server "$KEYCLOAK_URL" --realm master --user "$KEYCLOAK_ADMIN"
```

## OS support

Debian and Ubuntu, on amd64 and arm64. `official` needs `tar`, installs
`curl` and `ca-certificates` if `curl` is missing, and installs
`default-jre-headless` unless `install_jre` is `false`. `rest` installs
`curl`, `ca-certificates` and `python3` if they are missing.
