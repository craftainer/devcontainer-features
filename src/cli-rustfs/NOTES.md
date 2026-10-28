## Pinning the version

This feature has no default version. You choose the rc release and supply
the sha256 of its `.deb` for each arch you build on, and the install fails
unless it finds both. The download is always checked against your sha256;
the feature never fetches upstream's checksum file, so the sha you review
is the one that counts.

Get the shas from the release's `SHA256SUMS` on
[github.com/rustfs/cli/releases](https://github.com/rustfs/cli/releases):

| Arch | Package |
| --- | --- |
| amd64 | `rustfs-cli_<version>_amd64.deb` |
| arm64 | `rustfs-cli_<version>_arm64.deb` |

The version is the release number without the leading `v` (`0.1.36`, not
`v0.1.36`). You only need the sha for the arches you actually build on.
The package installs the statically linked `rc` binary as `/usr/bin/rc`,
with shell completions.

The pin can come from three places. The feature uses the first one that
sets either the version or a sha, and that place must set both: a version
in one place is never paired with a sha from another.

### 1. Feature options

```jsonc
"features": {
  "ghcr.io/craftainer/devcontainer-features/cli-rustfs:1": {
    "version": "0.1.36",
    "sha256_amd64": "2eb2d646b04206112c44d65ad5107edf1d164fc93f705c978397bc11eb29a95f",
    "sha256_arm64": "c5ad321059d6478994ee7f07abe131b81def0a09352f08df6eb982c612659ccb"
  }
}
```

To keep the pin out of `devcontainer.json`, feed the options from the
host's environment:

```jsonc
"ghcr.io/craftainer/devcontainer-features/cli-rustfs:1": {
  "version": "${localEnv:CLI_RUSTFS_VERSION}",
  "sha256_amd64": "${localEnv:CLI_RUSTFS_SHA256_AMD64}",
  "sha256_arm64": "${localEnv:CLI_RUSTFS_SHA256_ARM64}"
}
```

### 2. Environment variables in your image

Set `CLI_RUSTFS_VERSION`, `CLI_RUSTFS_SHA256_AMD64` and
`CLI_RUSTFS_SHA256_ARM64` with `ENV` in the Dockerfile your devcontainer
builds from, and leave the feature's options empty:

```dockerfile
ENV CLI_RUSTFS_VERSION=0.1.36
ENV CLI_RUSTFS_SHA256_AMD64=2eb2d646b04206112c44d65ad5107edf1d164fc93f705c978397bc11eb29a95f
ENV CLI_RUSTFS_SHA256_ARM64=c5ad321059d6478994ee7f07abe131b81def0a09352f08df6eb982c612659ccb
```

```jsonc
"build": { "dockerfile": "Dockerfile" },
"features": {
  "ghcr.io/craftainer/devcontainer-features/cli-rustfs:1": {}
}
```

### 3. A pins file in your image

Put the same `KEY=value` lines in a file and `COPY` it into the image at
`/etc/devcontainer-features/pins.env`. One file can hold the pins of every
feature in this collection; each feature reads only its own keys.

```sh
# pins.env
CLI_RUSTFS_VERSION=0.1.36
CLI_RUSTFS_SHA256_AMD64=2eb2d646b04206112c44d65ad5107edf1d164fc93f705c978397bc11eb29a95f
CLI_RUSTFS_SHA256_ARM64=c5ad321059d6478994ee7f07abe131b81def0a09352f08df6eb982c612659ccb
```

```dockerfile
COPY pins.env /etc/devcontainer-features/pins.env
```

The file is parsed, never sourced: `KEY=value` lines (optionally after
`export`), `#` comments and quoted values are understood, and nothing is
expanded. To keep it somewhere else, set the `pins_file` option to its
path in the image:

```jsonc
"ghcr.io/craftainer/devcontainer-features/cli-rustfs:1": {
  "pins_file": "/opt/pins/devcontainer.env"
}
```

## Install order with `ssl-ca`

If you also use this collection's `ssl-ca` feature for a corporate root
CA, the CA has to be trusted before the rc package is downloaded. This
feature deliberately declares no `installsAfter` on `ssl-ca`: the Dev
Container CLI fetches every `installsAfter` reference from ghcr.io, so
declaring one would make every build reach ghcr.io for `ssl-ca` even when
you don't use it. If you use `ssl-ca`, list it first in
`overrideFeatureInstallOrder`:

```jsonc
"overrideFeatureInstallOrder": [
  "ghcr.io/craftainer/devcontainer-features/ssl-ca",
  "ghcr.io/craftainer/devcontainer-features/cli-rustfs"
]
```

## Credentials

The feature installs only the package: it declares no mounts and stores no
state. rc doesn't read the `AWS_*` environment variables
(`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and so on). Each command uses
the endpoint and keys of an alias, which `rc alias set` stores in rc's own
config file, `~/.config/rc/config.toml` (or `$RC_CONFIG_DIR/config.toml`
when `RC_CONFIG_DIR` is set).

Rather than keeping that file in a volume, create the alias each time the
container is created, from variables you pass in from the host. The
variable names below are only examples; rc doesn't read them itself.

```jsonc
"containerEnv": {
  "RUSTFS_ENDPOINT": "${localEnv:RUSTFS_ENDPOINT}",
  "RUSTFS_ACCESS_KEY": "${localEnv:RUSTFS_ACCESS_KEY}",
  "RUSTFS_SECRET_KEY": "${localEnv:RUSTFS_SECRET_KEY}"
},
"postCreateCommand": "rc alias set local \"$RUSTFS_ENDPOINT\" \"$RUSTFS_ACCESS_KEY\" \"$RUSTFS_SECRET_KEY\""
```

With Docker Compose, the same variables can come from an `env_file` that
stays out of version control:

```yaml
services:
  devcontainer:
    env_file: .secrets/s3.env
```

`rc alias set` checks the keys against the endpoint (a ListBuckets call)
before saving the alias, and saves nothing if the endpoint can't be
reached. So the S3 service has to be up when the command runs: with Docker
Compose, make the devcontainer service `depends_on` it with
`condition: service_healthy`. If the alias is missing, run the same
command again once the service is up. `rc alias set` replaces an alias of
the same name, so the command is safe to run on every create. See
`rc alias set --help` for `--region`, `--bucket-lookup`, `--insecure` and
`--ca-bundle`.

## OS support

Debian and Ubuntu, on amd64 and arm64. The package's binary is statically
linked, so it needs no particular glibc. The install runs `apt-get update`
and `apt-get install` for the downloaded `.deb`, and installs `curl` and
`ca-certificates` first if either is missing.
