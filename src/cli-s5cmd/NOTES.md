## Pinning the version

This feature has no default version. You choose the s5cmd release and
supply the sha256 of its tarball for each arch you build on, and the
install fails unless it finds both. The download is always checked against
your sha256; the feature never fetches upstream's checksum file, so the
sha you review is the one that counts.

Get the shas from the release's `s5cmd_checksums.txt` on
[github.com/peak/s5cmd/releases](https://github.com/peak/s5cmd/releases):

| Arch | Tarball |
| --- | --- |
| amd64 | `s5cmd_<version>_Linux-64bit.tar.gz` |
| arm64 | `s5cmd_<version>_Linux-arm64.tar.gz` |

The version is the release number without the leading `v` (`2.3.0`, not
`v2.3.0`). You only need the sha for the arches you actually build on.

The pin can come from three places. The feature uses the first one that
sets either the version or a sha, and that place must set both: a version
in one place is never paired with a sha from another.

### 1. Feature options

```jsonc
"features": {
  "ghcr.io/craftainer/devcontainer-features/cli-s5cmd:1": {
    "version": "2.3.0",
    "sha256_amd64": "de0fdbfa3aceae55e069ba81a0fc17b2026567637603734a387b2fca06c299b4",
    "sha256_arm64": "1439f0d00ecedcd2a2f1f2c6749bbb0152b2257bf5086f29646ec8ae38798e24"
  }
}
```

To keep the pin out of `devcontainer.json`, feed the options from the
host's environment:

```jsonc
"ghcr.io/craftainer/devcontainer-features/cli-s5cmd:1": {
  "version": "${localEnv:CLI_S5CMD_VERSION}",
  "sha256_amd64": "${localEnv:CLI_S5CMD_SHA256_AMD64}",
  "sha256_arm64": "${localEnv:CLI_S5CMD_SHA256_ARM64}"
}
```

### 2. Environment variables in your image

Set `CLI_S5CMD_VERSION`, `CLI_S5CMD_SHA256_AMD64` and
`CLI_S5CMD_SHA256_ARM64` with `ENV` in the Dockerfile your devcontainer
builds from, and leave the feature's options empty:

```dockerfile
ENV CLI_S5CMD_VERSION=2.3.0
ENV CLI_S5CMD_SHA256_AMD64=de0fdbfa3aceae55e069ba81a0fc17b2026567637603734a387b2fca06c299b4
ENV CLI_S5CMD_SHA256_ARM64=1439f0d00ecedcd2a2f1f2c6749bbb0152b2257bf5086f29646ec8ae38798e24
```

```jsonc
"build": { "dockerfile": "Dockerfile" },
"features": {
  "ghcr.io/craftainer/devcontainer-features/cli-s5cmd:1": {}
}
```

### 3. A pins file in your image

Put the same `KEY=value` lines in a file and `COPY` it into the image at
`/etc/devcontainer-features/pins.env`. One file can hold the pins of every
feature in this collection; each feature reads only its own keys.

```sh
# pins.env
CLI_S5CMD_VERSION=2.3.0
CLI_S5CMD_SHA256_AMD64=de0fdbfa3aceae55e069ba81a0fc17b2026567637603734a387b2fca06c299b4
CLI_S5CMD_SHA256_ARM64=1439f0d00ecedcd2a2f1f2c6749bbb0152b2257bf5086f29646ec8ae38798e24
```

```dockerfile
COPY pins.env /etc/devcontainer-features/pins.env
```

The file is parsed, never sourced: `KEY=value` lines (optionally after
`export`), `#` comments and quoted values are understood, and nothing is
expanded. To keep it somewhere else, set the `pins_file` option to its
path in the image:

```jsonc
"ghcr.io/craftainer/devcontainer-features/cli-s5cmd:1": {
  "pins_file": "/opt/pins/devcontainer.env"
}
```

## Install order with `ssl-ca`

If you also use this collection's `ssl-ca` feature for a corporate root
CA, the CA has to be trusted before s5cmd is downloaded. This feature
deliberately declares no `installsAfter` on `ssl-ca`: the Dev Container
CLI fetches every `installsAfter` reference from ghcr.io, so declaring one
would make every build reach ghcr.io for `ssl-ca` even when you don't use
it. If you use `ssl-ca`, list it first in `overrideFeatureInstallOrder`:

```jsonc
"overrideFeatureInstallOrder": [
  "ghcr.io/craftainer/devcontainer-features/ssl-ca",
  "ghcr.io/craftainer/devcontainer-features/cli-s5cmd"
]
```

## Credentials

The feature installs only the binary: it declares no mounts and stores no
state. s5cmd uses the AWS SDK, so it reads the usual `AWS_*` environment
variables (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`,
`AWS_SESSION_TOKEN`, `AWS_REGION`, `AWS_PROFILE`), plus `S3_ENDPOINT_URL`
for an S3-compatible service such as RustFS or MinIO. Pass them in from
the host instead of baking them into the image:

```jsonc
"containerEnv": {
  "AWS_ACCESS_KEY_ID": "${localEnv:AWS_ACCESS_KEY_ID}",
  "AWS_SECRET_ACCESS_KEY": "${localEnv:AWS_SECRET_ACCESS_KEY}",
  "AWS_REGION": "${localEnv:AWS_REGION}",
  "S3_ENDPOINT_URL": "${localEnv:S3_ENDPOINT_URL}"
}
```

or, with Docker Compose, from an `env_file` that stays out of version
control:

```yaml
services:
  devcontainer:
    env_file: .secrets/s3.env
```

## OS support

Debian and Ubuntu, on amd64 and arm64. The install needs `tar`, and
installs `curl` and `ca-certificates` if `curl` is missing.
