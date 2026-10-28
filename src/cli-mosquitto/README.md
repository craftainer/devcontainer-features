
# Mosquitto MQTT clients (cli-mosquitto)

Installs the Eclipse Mosquitto MQTT clients (mosquitto_pub, mosquitto_sub, mosquitto_rr) at an exact upstream version you choose, e.g. 2.0.22: on Debian from repo.mosquitto.org, whose signing key the feature pins by fingerprint, on Ubuntu from the distro's own archive. The versions available differ by distro. There are no default pins.

## Example Usage

```json
"features": {
    "ghcr.io/craftainer/devcontainer-features/cli-mosquitto:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| version | Mosquitto clients version to install, as the upstream version (e.g. 2.0.22), with no leading v and no Debian revision. It must exist for your distro (see the notes). Set it here, or as CLI_MOSQUITTO_VERSION in the image environment, or in the pins file. There is no default. | string | - |
| pins_file | Path of the pins file in the image, read when neither the options nor the image environment set the version. Empty means /etc/devcontainer-features/pins.env. | string | - |

## What it installs

The Eclipse Mosquitto MQTT clients from the `mosquitto-clients` package, at
the exact upstream version you pin: `mosquitto_pub`, `mosquitto_sub` and
`mosquitto_rr`, in `/usr/bin`. Their library, `libmosquitto1`, is installed
at the same version. No broker is installed.

Mosquitto publishes no prebuilt Linux binaries, so the package comes from
apt, and where it comes from depends on the distro:

- **Debian:** from [repo.mosquitto.org](https://repo.mosquitto.org/debian/README.txt),
  the Mosquitto project's own repository, which carries exact 2.0.x and
  2.1.x builds. The feature adds its `<codename> main` suite.
- **Ubuntu:** from Ubuntu's own archive (`universe`). No repository is
  added.

Any other distribution fails the install, including Debian or Ubuntu
derivatives with another `ID` in `/etc/os-release`.

After installing, the feature checks that all three clients are on `PATH`
and that each reports the pinned version, on a `libmosquitto` of the same
version.

## Which versions exist where

**A pin is distro-specific.** The two sources carry different versions, so
a pin that installs on Debian can fail on Ubuntu, and the other way round.
As of 2026-10-28:

| Distro | Source | Versions (`mosquitto-clients`) |
| --- | --- | --- |
| Debian 13 (trixie) | repo.mosquitto.org, `trixie main` | 2.0.22, 2.1.0, 2.1.1, 2.1.2 (revisions `0mosquittoN~trixie1`) |
| Debian 13 (trixie) | Debian's own archive | 2.0.21 (`2.0.21-1`) |
| Ubuntu 24.04 (noble) | Ubuntu's archive, `universe` | 2.0.18 (`2.0.18-1build3`) |

Sources: repo.mosquitto.org's
[`dists/trixie/main/binary-amd64/Packages`](https://repo.mosquitto.org/debian/dists/trixie/main/binary-amd64/Packages)
and `binary-arm64/Packages` (the same versions on both arches), Debian's
[madison for mosquitto-clients](https://qa.debian.org/madison.php?package=mosquitto-clients&text=on),
and Launchpad's
[publishing history for noble](https://launchpad.net/ubuntu/+source/mosquitto/+publishinghistory)
(no newer build in `noble-updates` or `noble-security`).
repo.mosquitto.org serves `bookworm`, `bullseye` and `trixie` (and the
frozen `buster` and `stretch`); see its
[list of suites](https://repo.mosquitto.org/debian/dists/). Check these
before you choose a pin: the lists change as new versions are released.

So `2.0.22` (or `2.1.2`) works on Debian 13 and `2.0.18` on Ubuntu 24.04.
If your team builds on both, keep one pin per image, for example in each
image's pins file.

### Several sources, one version: the highest Debian revision wins

On Debian, both repo.mosquitto.org and Debian's archive are configured.
When both carry the same upstream version, the feature installs the
**highest Debian revision**, whichever source it comes from
([ADR 0003](../../docs/adrs/0003-pin-apt-installed-clis-by-upstream-version-with-a-verified-repo-key.md)).
It ignores apt pin priorities. For example, if a Debian point release
shipped `2.0.22-1`, the distro's `2.0.22-1` would win over
repo.mosquitto.org's `2.0.22-0mosquitto1~trixie1`. Today the two don't
overlap: repo.mosquitto.org has no 2.0.21 for trixie, so a `2.0.21` pin on
Debian 13 installs Debian's own `2.0.21-1`. When one source carries several
rebuilds of a version (repo.mosquitto.org has 2.1.0 up to
`0mosquitto4~trixie1`), the highest
is installed as well, and a later rebuild is picked up by the next build
without a pin change.

### When a pin doesn't resolve

A version your distro's sources don't have (e.g. `2.0.99`, or `2.0.22` on
Ubuntu 24.04) fails, and the error lists the versions available. The
feature never downgrades: if the image already has a newer
`mosquitto-clients` or `libmosquitto1`, apt refuses the install, and the
feature fails rather than forcing it.

A pinned version keeps resolving as long as a source still carries it.
Ubuntu's release pocket (`noble`) is frozen at release, so `2.0.18` stays
available there. A security update to it would land in `noble-security`
and `noble-updates` as a newer revision of the same upstream version
(say `2.0.18-1ubuntu0.1`), which the feature would then install as the
highest revision; those two pockets keep only their newest revision.
Debian's stable archive replaces a package at each point release, so a
version only Debian's archive carries (today `2.0.21` on trixie) can stop
resolving when a point release moves to a new upstream version. The
feature uses no snapshot archive (snapshot.debian.org or
snapshot.ubuntu.com) to keep old revisions installable.

## Pinning the version

This feature has no default version. You choose the Mosquitto release,
and the install fails unless it finds one.

The version is the **upstream** version: digits and dots, e.g. `2.0.22`. It
has no leading `v` and no Debian revision. `v2.0.22`,
`2.0.22-0mosquitto1~trixie1` and `2.0.` are rejected.

The pin can come from three places. The feature uses the first one that
sets it.

### 1. Feature options

```jsonc
"features": {
  "ghcr.io/craftainer/devcontainer-features/cli-mosquitto:1": {
    "version": "2.0.22"
  }
}
```

To keep the pin out of `devcontainer.json`, feed the option from the host's
environment:

```jsonc
"ghcr.io/craftainer/devcontainer-features/cli-mosquitto:1": {
  "version": "${localEnv:CLI_MOSQUITTO_VERSION}"
}
```

### 2. An environment variable in your image

Set `CLI_MOSQUITTO_VERSION` with `ENV` in the Dockerfile your devcontainer
builds from, and leave the feature's options empty:

```dockerfile
ENV CLI_MOSQUITTO_VERSION=2.0.22
```

```jsonc
"build": { "dockerfile": "Dockerfile" },
"features": {
  "ghcr.io/craftainer/devcontainer-features/cli-mosquitto:1": {}
}
```

### 3. A pins file in your image

Put a `KEY=value` line in a file and `COPY` it into the image at
`/etc/devcontainer-features/pins.env`. One file can hold the pins of every
feature in this collection, and each feature reads only its own keys.

```sh
# pins.env
CLI_MOSQUITTO_VERSION=2.0.22
```

```dockerfile
COPY pins.env /etc/devcontainer-features/pins.env
```

The file is parsed, never sourced. The feature understands `KEY=value`
lines (optionally after `export`), `#` comments and quoted values, and
expands nothing. To keep the file somewhere else, set the `pins_file`
option to its path in the image:

```jsonc
"ghcr.io/craftainer/devcontainer-features/cli-mosquitto:1": {
  "pins_file": "/opt/pins/devcontainer.env"
}
```

## Trust model: no sha

Unlike this collection's download features, you supply no sha256 here.
The `.deb` differs per distro, arch and source, so a sha pin would need a
set of shas nobody can keep current. Instead, apt checks every package
against its repository's signed index
([ADR 0003](../../docs/adrs/0003-pin-apt-installed-clis-by-upstream-version-with-a-verified-repo-key.md)):

- **Debian:** the feature pins repo.mosquitto.org's signing key by a
  fingerprint constant, `8277CCB49EC5B595F2D2C71361611AE430993623`, as the
  official devcontainers features do. It fetches
  `https://repo.mosquitto.org/debian/mosquitto-repo.gpg` over https and
  checks that the exact key bytes it installs hold one primary key with
  that fingerprint. Then it writes the key to
  `/etc/apt/keyrings/mosquitto.gpg`, and
  `/etc/apt/sources.list.d/mosquitto.list` trusts only that key file
  (`signed-by`). A different key fails the install before anything is
  written. If the Mosquitto project rotates its key, the feature needs a
  new release. Debian's own archive stays trusted through the image's
  own Debian keyring, as before.
- **Ubuntu:** nothing is added. The package comes from Ubuntu's archive,
  signed with the Ubuntu archive key the image already trusts.

On Debian, the install installs `curl`, `ca-certificates` and `gpg` if any
of them is missing, and leaves them in the image.

## Install order with `ssl-ca`

On Debian, repo.mosquitto.org is reached over https. Behind a
TLS-intercepting proxy, your corporate root CA must be trusted before this
feature runs. This feature deliberately declares no `installsAfter` on
`ssl-ca`: the Dev Container CLI fetches every `installsAfter` reference
from ghcr.io, so declaring one would make every build reach ghcr.io for
`ssl-ca`, even when you don't use it. If you use this collection's
`ssl-ca` feature, list it first in `overrideFeatureInstallOrder`:

```jsonc
"overrideFeatureInstallOrder": [
  "ghcr.io/craftainer/devcontainer-features/ssl-ca",
  "ghcr.io/craftainer/devcontainer-features/cli-mosquitto"
]
```

## Credentials

The feature installs only the clients. It declares no mounts and stores no
state. The clients read **no environment variables** for the broker or
its credentials (only `XDG_CONFIG_HOME` and `HOME`, to find their config
file). Give them on the command line, with `-h`, `-p`, `-u` (`--username`)
and `-P` (`--pw`), or as one `-L mqtt://user:password@host:port/topic` URL.
Pass the values in from the host instead of baking them into the image:

```jsonc
"containerEnv": {
  "MQTT_HOST": "mqtt",
  "MQTT_USERNAME": "${localEnv:MQTT_USERNAME}",
  "MQTT_PASSWORD": "${localEnv:MQTT_PASSWORD}"
}
```

```sh
mosquitto_sub -h "$MQTT_HOST" -u "$MQTT_USERNAME" -P "$MQTT_PASSWORD" -t 'sensors/#'
```

or, with Docker Compose, from an `env_file` that stays out of version
control (`env_file: .secrets/mqtt.env`).

A password given with `-P` is visible to other processes in the container
(`ps`). To keep it off the command line, use the clients' config file. The
[mosquitto_pub man page](https://mosquitto.org/man/mosquitto_pub-1.html)
says:

> The options below may be given on the command line, but may also be
> placed in a config file located at `$XDG_CONFIG_HOME/mosquitto_pub` or
> `$HOME/.config/mosquitto_pub` with one pair of `-option value` per line.
> The values in the config file will be used as defaults and can be
> overridden by using the command line.

Each client reads its own file: `mosquitto_pub`, `mosquitto_sub` and
`mosquitto_rr` under `~/.config/` (or `$XDG_CONFIG_HOME`). Write them in a
`postCreateCommand`, from the variables above, with mode `0600`:

```jsonc
"postCreateCommand": "mkdir -p ~/.config && for t in mosquitto_pub mosquitto_sub mosquitto_rr; do (umask 077 && printf -- '-h %s\\n-u %s\\n-P %s\\n' \"$MQTT_HOST\" \"$MQTT_USERNAME\" \"$MQTT_PASSWORD\" >~/.config/$t); done"
```

## OS support

Debian 13 (trixie) and Ubuntu 24.04 (noble), on amd64 and arm64. On Debian
the suite is chosen from `VERSION_CODENAME` in `/etc/os-release`; a release
repo.mosquitto.org doesn't serve fails the install with a pointer to
[its list of suites](https://repo.mosquitto.org/debian/dists/). On Ubuntu
any release works whose archive carries the version you pin.


---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/craftainer/devcontainer-features/blob/main/src/cli-mosquitto/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
