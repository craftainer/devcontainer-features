
# valkey-cli (cli-valkey)

Installs valkey-cli, the Valkey command-line client, from upstream's binary release at an exact version, checked against a sha256 you supply. There are no default pins.

## Example Usage

```json
"features": {
    "ghcr.io/craftainer/devcontainer-features/cli-valkey:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| version | Valkey version to install, without a leading v (e.g. 9.1.3). Set it with its sha256 here, or as CLI_VALKEY_VERSION in the image environment, or in the pins file. There is no default. | string | - |
| sha256_amd64 | sha256 of valkey-<version>-noble-x86_64.tar.gz, needed on amd64. Set it here, or as CLI_VALKEY_SHA256_AMD64 in the image environment, or in the pins file, in the same place as the version. | string | - |
| sha256_arm64 | sha256 of valkey-<version>-noble-arm64.tar.gz, needed on arm64. Set it here, or as CLI_VALKEY_SHA256_ARM64 in the image environment, or in the pins file, in the same place as the version. | string | - |
| pins_file | Path of the pins file in the image, read when neither the options nor the image environment set a pin. Empty means /etc/devcontainer-features/pins.env. | string | - |

## What it installs

`valkey-cli`, as `/usr/local/bin/valkey-cli`, from upstream's prebuilt
binary release on [valkey.io/download](https://valkey.io/download/). The
release tarball (about 40 MB) also carries `valkey-server`,
`valkey-sentinel`, `valkey-benchmark` and the check tools; the feature
extracts only `bin/valkey-cli` and the license notice (see
[License](#license)) and installs no other binary. No `redis-cli` alias is
created.

The feature always uses upstream's Ubuntu 24.04 (`noble`) build, on Debian
too. That build needs glibc 2.38 or later and OpenSSL 3 (`libssl.so.3`,
`libcrypto.so.3`). Debian 13 (glibc 2.41) and Ubuntu 24.04 (glibc 2.39)
have glibc new enough. OpenSSL 3 is in their base images today only as a
dependency of other packages, so when `ldconfig` finds no `libssl.so.3`
the feature installs `libssl3t64` (OpenSSL 3's package on both distros)
from the distro's archive. Otherwise nothing extra is installed. Older
distros such as Debian 12 or Ubuntu 22.04 are not supported; upstream's
`jammy` build exists for those, but this feature doesn't use it.

## Pinning the version

This feature has no default version. You choose the Valkey release and
supply the sha256 of its tarball for each arch you build on, and the
install fails unless it finds both. The download is always checked against
your sha256; the feature never fetches upstream's `.sha256` file, so the
sha you review is the one that counts. Pick the release that matches your
Valkey server, e.g. `9.1.3` for a 9.1 server.

Get the shas from the `.sha256` file next to each tarball on
[valkey.io/download](https://valkey.io/download/) (each version page, such
as [9.1](https://valkey.io/download/9.1/), links them):

| Arch | Tarball |
| --- | --- |
| amd64 | `https://download.valkey.io/releases/valkey-<version>-noble-x86_64.tar.gz` |
| arm64 | `https://download.valkey.io/releases/valkey-<version>-noble-arm64.tar.gz` |

The version is the release number, which has no leading `v` (`9.1.3`).
You only need the sha for the arches you actually build on.

This is a download feature with a consumer sha, like `cli-s5cmd`, not one
of the apt-installed CLIs (`cli-postgres-client`, `cli-mosquitto`) that pin
a version only (see
[ADR 0003](../../docs/adrs/0003-pin-apt-installed-clis-by-upstream-version-with-a-verified-repo-key.md),
which doesn't cover this feature).

The pin can come from three places. The feature uses the first one that
sets either the version or a sha, and that place must set both: a version
in one place is never paired with a sha from another.

### 1. Feature options

```jsonc
"features": {
  "ghcr.io/craftainer/devcontainer-features/cli-valkey:1": {
    "version": "9.1.3",
    "sha256_amd64": "26416df8a5b075ffb7d549e9a6445db9ec16e36d2259d8ea6e010dca35d53a54",
    "sha256_arm64": "bf77cf1adf9dc2b1e1f42a01b611b5b8d00c5c158a200ab9ad1f8837d84d59da"
  }
}
```

To keep the pin out of `devcontainer.json`, feed the options from the
host's environment:

```jsonc
"ghcr.io/craftainer/devcontainer-features/cli-valkey:1": {
  "version": "${localEnv:CLI_VALKEY_VERSION}",
  "sha256_amd64": "${localEnv:CLI_VALKEY_SHA256_AMD64}",
  "sha256_arm64": "${localEnv:CLI_VALKEY_SHA256_ARM64}"
}
```

### 2. Environment variables in your image

Set `CLI_VALKEY_VERSION`, `CLI_VALKEY_SHA256_AMD64` and
`CLI_VALKEY_SHA256_ARM64` with `ENV` in the Dockerfile your devcontainer
builds from, and leave the feature's options empty:

```dockerfile
ENV CLI_VALKEY_VERSION=9.1.3
ENV CLI_VALKEY_SHA256_AMD64=26416df8a5b075ffb7d549e9a6445db9ec16e36d2259d8ea6e010dca35d53a54
ENV CLI_VALKEY_SHA256_ARM64=bf77cf1adf9dc2b1e1f42a01b611b5b8d00c5c158a200ab9ad1f8837d84d59da
```

```jsonc
"build": { "dockerfile": "Dockerfile" },
"features": {
  "ghcr.io/craftainer/devcontainer-features/cli-valkey:1": {}
}
```

### 3. A pins file in your image

Put the same `KEY=value` lines in a file and `COPY` it into the image at
`/etc/devcontainer-features/pins.env`. One file can hold the pins of every
feature in this collection; each feature reads only its own keys.

```sh
# pins.env
CLI_VALKEY_VERSION=9.1.3
CLI_VALKEY_SHA256_AMD64=26416df8a5b075ffb7d549e9a6445db9ec16e36d2259d8ea6e010dca35d53a54
CLI_VALKEY_SHA256_ARM64=bf77cf1adf9dc2b1e1f42a01b611b5b8d00c5c158a200ab9ad1f8837d84d59da
```

```dockerfile
COPY pins.env /etc/devcontainer-features/pins.env
```

The file is parsed, never sourced: `KEY=value` lines (optionally after
`export`), `#` comments and quoted values are understood, and nothing is
expanded. To keep it somewhere else, set the `pins_file` option to its
path in the image:

```jsonc
"ghcr.io/craftainer/devcontainer-features/cli-valkey:1": {
  "pins_file": "/opt/pins/devcontainer.env"
}
```

## Install order with `ssl-ca`

If you also use this collection's `ssl-ca` feature for a corporate root
CA, the CA has to be trusted before the tarball is downloaded. This feature
deliberately declares no `installsAfter` on `ssl-ca`: the Dev Container
CLI fetches every `installsAfter` reference from ghcr.io, so declaring one
would make every build reach ghcr.io for `ssl-ca` even when you don't use
it. If you use `ssl-ca`, list it first in `overrideFeatureInstallOrder`:

```jsonc
"overrideFeatureInstallOrder": [
  "ghcr.io/craftainer/devcontainer-features/ssl-ca",
  "ghcr.io/craftainer/devcontainer-features/cli-valkey"
]
```

## Credentials

The feature installs only the binary: it declares no mounts and stores no
state. For a password-protected server, pass the password in the
environment instead of with `-a`, which puts it on the command line.
`valkey-cli` reads `VALKEYCLI_AUTH`, and falls back to `REDISCLI_AUTH`
when that isn't set; `-a` or `--pass` win over both
([`parseEnv` in valkey-cli.c](https://github.com/valkey-io/valkey/blob/9.1.3/src/valkey-cli.c)).
`REDISCLI_AUTH` also works with `redis-cli`, so it suits a project that
uses both. Add `--user <name>` for an ACL user. Pass the variable in from
the host instead of baking it into the image:

```jsonc
"containerEnv": {
  "REDISCLI_AUTH": "${localEnv:VALKEY_PASSWORD}"
}
```

or, with Docker Compose, from an `env_file` that stays out of version
control:

```yaml
services:
  devcontainer:
    env_file: .secrets/valkey.env
```

## OS support

Debian 13 and Ubuntu 24.04 or later, on amd64 and arm64 (see "What it
installs" for the glibc and OpenSSL requirement). The install needs `tar`,
and installs `curl`, `ca-certificates` and `libssl3t64` if any is missing.

## License

Valkey is BSD-3-Clause ([COPYING](https://github.com/valkey-io/valkey/blob/unstable/COPYING)); the feature installs the notice from the release tarball (`share/LICENSE`) as `/usr/local/share/doc/valkey-cli/LICENSE`.


---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/craftainer/devcontainer-features/blob/main/src/cli-valkey/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
