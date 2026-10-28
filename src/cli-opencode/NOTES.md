## What it installs

The [opencode](https://opencode.ai) AI coding agent from the
[`anomalyco/opencode`](https://github.com/anomalyco/opencode) releases
(formerly `sst/opencode`), as `/usr/local/bin/opencode`. The feature:

- downloads
  `https://github.com/anomalyco/opencode/releases/download/v<version>/opencode-linux-{x64,arm64}.tar.gz`,
  checks it against your sha256 and installs the `opencode` binary from
  it;
- creates `~/.config/opencode` and `~/.local/share/opencode` for the
  remote user, mode `0700` (see
  [Keeping the login across rebuilds](#keeping-the-login-across-rebuilds));
- sets `OPENCODE_DISABLE_AUTOUPDATE=1` in the container environment, so
  opencode doesn't check for or offer updates away from your pin (see
  [Bumping the version](#bumping-the-version)).

It declares no mounts and sets no state-path variable such as
`OPENCODE_CONFIG_DIR`: where opencode's state and credentials live is your
choice, not the feature's.

The x64 build is the one opencode's own installer
(`https://opencode.ai/install`) picks for a CPU with AVX2. The releases
also carry `opencode-linux-x64-baseline.tar.gz` for x64 CPUs without
AVX2, and `*-musl` builds for Alpine; this feature installs neither.

## Pinning the version

This feature has no default version. You choose the opencode release and
supply the sha256 of its tarball for each arch you build on, and the
install fails unless it finds both. The download is always checked against
your sha256.

opencode doesn't publish a checksums file, but GitHub shows each release
asset's sha256 (its `digest`), and you can compute it from the download
yourself:

```sh
VERSION=1.19.5
gh release view "v${VERSION}" --repo anomalyco/opencode --json assets \
  --jq '.assets[] | select(.name == "opencode-linux-x64.tar.gz" or .name == "opencode-linux-arm64.tar.gz") | "\(.name) \(.digest | ltrimstr("sha256:"))"'
# or
for a in x64 arm64; do
  printf '%s ' "opencode-linux-${a}.tar.gz"
  curl -fsSL "https://github.com/anomalyco/opencode/releases/download/v${VERSION}/opencode-linux-${a}.tar.gz" | sha256sum
done
```

| Arch | Asset |
| --- | --- |
| amd64 | `opencode-linux-x64.tar.gz` |
| arm64 | `opencode-linux-arm64.tar.gz` |

The version is the release tag without its `v` (`1.19.5` for tag
`v1.19.5`); a leading `v` is rejected. You only need the sha for the
arches you actually build on.

The pin can come from three places. The feature uses the first one that
sets either the version or a sha, and that place must set both: a version
in one place is never paired with a sha from another.

### 1. Feature options

```jsonc
"features": {
  "ghcr.io/craftainer/devcontainer-features/cli-opencode:1": {
    "version": "1.19.5",
    "sha256_amd64": "588310a336fa3b9df36b3f0225b26f679d453efaad0cf3d66c3651ef3ec1647a",
    "sha256_arm64": "fae5be262d693b7c5e562856cc473e59e741772936db0c0600ac0d5ed5bd088b"
  }
}
```

To keep the pin out of `devcontainer.json`, feed the options from the
host's environment:

```jsonc
"ghcr.io/craftainer/devcontainer-features/cli-opencode:1": {
  "version": "${localEnv:CLI_OPENCODE_VERSION}",
  "sha256_amd64": "${localEnv:CLI_OPENCODE_SHA256_AMD64}",
  "sha256_arm64": "${localEnv:CLI_OPENCODE_SHA256_ARM64}"
}
```

### 2. Environment variables in your image

Set `CLI_OPENCODE_VERSION`, `CLI_OPENCODE_SHA256_AMD64` and
`CLI_OPENCODE_SHA256_ARM64` with `ENV` in the Dockerfile your devcontainer
builds from, and leave the feature's options empty:

```dockerfile
ENV CLI_OPENCODE_VERSION=1.19.5
ENV CLI_OPENCODE_SHA256_AMD64=588310a336fa3b9df36b3f0225b26f679d453efaad0cf3d66c3651ef3ec1647a
ENV CLI_OPENCODE_SHA256_ARM64=fae5be262d693b7c5e562856cc473e59e741772936db0c0600ac0d5ed5bd088b
```

```jsonc
"build": { "dockerfile": "Dockerfile" },
"features": {
  "ghcr.io/craftainer/devcontainer-features/cli-opencode:1": {}
}
```

### 3. A pins file in your image

Put the same `KEY=value` lines in a file and `COPY` it into the image at
`/etc/devcontainer-features/pins.env`. One file can hold the pins of every
feature in this collection; each feature reads only its own keys.

```sh
# pins.env
CLI_OPENCODE_VERSION=1.19.5
CLI_OPENCODE_SHA256_AMD64=588310a336fa3b9df36b3f0225b26f679d453efaad0cf3d66c3651ef3ec1647a
CLI_OPENCODE_SHA256_ARM64=fae5be262d693b7c5e562856cc473e59e741772936db0c0600ac0d5ed5bd088b
```

```dockerfile
COPY pins.env /etc/devcontainer-features/pins.env
```

The file is parsed, never sourced: `KEY=value` lines (optionally after
`export`), `#` comments and quoted values are understood, and nothing is
expanded. To keep it somewhere else, set the `pins_file` option to its
path in the image:

```jsonc
"ghcr.io/craftainer/devcontainer-features/cli-opencode:1": {
  "pins_file": "/opt/pins/devcontainer.env"
}
```

## Bumping the version

opencode checks for new versions in the background and shows a notice
when one is available; it doesn't install updates by itself, but `/update`
in the TUI and `opencode upgrade` do
([config: Autoupdate](https://opencode.ai/docs/config/#autoupdate)). This
feature sets `OPENCODE_DISABLE_AUTOUPDATE=1` in `containerEnv`, the
documented switch that "disable[s] update checks and notices"
([CLI: Environment variables](https://opencode.ai/docs/cli/#environment-variables)).
It has the same effect as `"autoupdate": false` in `opencode.json`, without
the feature writing your config.

To move to a newer release, change the pin: put the new version and its
two shas wherever you set the pin, and rebuild the container. Don't use
`opencode upgrade` or `/update` in this container. They don't replace
`/usr/local/bin/opencode`; depending on what they detect they fail, or
(with `--method curl`, or an `opencode-ai` npm package installed globally)
install a second, unpinned copy elsewhere, such as `~/.opencode/bin`, that
can shadow the pinned one on `PATH`.

## Keeping the login across rebuilds

opencode keeps its global config (`opencode.json`, agents, plugins) in
`~/.config/opencode`, and its data in `~/.local/share/opencode`: the
provider credentials you add with `/connect` in `auth.json`, session and
message history, and logs
([Troubleshooting: Storage](https://opencode.ai/docs/troubleshooting/#storage),
[Providers: Credentials](https://opencode.ai/docs/providers/#credentials)).
It also uses `~/.cache/opencode` (downloaded plugins and tools, which
opencode rebuilds when the directory is deleted) and
`~/.local/state/opencode` (run-time state); the docs put no credentials
in either, and this feature doesn't create them. A
rebuild discards all of them, so you sign in again each time unless you
choose one of the options below.

The feature declares no mount: a feature's mounts can't be switched off,
and whether credentials sit in a volume, and whether projects share one,
is a security choice that belongs to you. What it does is create
`~/.config/opencode` and `~/.local/share/opencode` in the image, owned by
the remote user with mode `0700`. Docker seeds an empty named volume with
the ownership of the directory it is mounted on, so volumes you mount
there start out writable by the remote user instead of owned by root.

In the snippets below, replace `/home/vscode` with your `remoteUser`'s
home directory (`/root` if the container runs as root). The config volume
is optional: if you keep `opencode.json` in your repository or dotfiles
instead, mount only the data directory.

### (a) Volumes per project

Each devcontainer gets its own volumes, named after its
`${devcontainerId}`. A login in one project isn't visible to another.

```jsonc
"mounts": [
  "source=opencode-data-${devcontainerId},target=/home/vscode/.local/share/opencode,type=volume",
  "source=opencode-config-${devcontainerId},target=/home/vscode/.config/opencode,type=volume"
]
```

### (b) Volumes shared by all projects

Sign in once and every devcontainer that mounts the same volume is signed
in. The trade-off: every container that mounts it can read the same
credentials, including a container for a repository you trust less.

```jsonc
"mounts": [
  "source=opencode-data,target=/home/vscode/.local/share/opencode,type=volume",
  "source=opencode-config,target=/home/vscode/.config/opencode,type=volume"
]
```

### (c) No volume, API keys from the host

Keep no credentials in the container at all and pass the provider's API
key in from the host's environment on every start. opencode loads a
provider whose API-key variable is set, without `/connect`; the variable
names come from [models.dev](https://models.dev), which opencode uses for
its provider list. Common ones:

| Provider | Variable |
| --- | --- |
| Anthropic | `ANTHROPIC_API_KEY` |
| OpenAI | `OPENAI_API_KEY` |
| Google (Gemini) | `GOOGLE_GENERATIVE_AI_API_KEY` or `GEMINI_API_KEY` |
| OpenRouter | `OPENROUTER_API_KEY` |
| Amazon Bedrock | `AWS_BEARER_TOKEN_BEDROCK`, or the usual `AWS_*` credentials |

The [providers](https://opencode.ai/docs/providers/) page lists the rest.
History doesn't survive a rebuild, but nothing secret is stored in a
volume, and revoking the key on the host side is enough. **This is the
recommended option for enterprise use.**

```jsonc
"containerEnv": {
  "ANTHROPIC_API_KEY": "${localEnv:ANTHROPIC_API_KEY}",
  "OPENAI_API_KEY": "${localEnv:OPENAI_API_KEY}"
}
```

## Install order

This feature deliberately declares no `installsAfter`: the Dev Container
CLI fetches every `installsAfter` reference from ghcr.io, so declaring one
would make every build reach ghcr.io for features you may not use. Set
the order yourself with `overrideFeatureInstallOrder` in these two cases.

- **`ssl-ca`.** If you use this collection's `ssl-ca` feature for a
  corporate root CA, the CA has to be trusted before opencode is
  downloaded, so list `ssl-ca` first.
- **A feature that creates the remote user**, such as
  `ghcr.io/devcontainers/features/common-utils` on an image without that
  user. This feature creates its state directories in the remote user's
  home, and the install fails if that home doesn't exist yet, so list the
  user-creating feature before this one.

```jsonc
"overrideFeatureInstallOrder": [
  "ghcr.io/devcontainers/features/common-utils",
  "ghcr.io/craftainer/devcontainer-features/ssl-ca",
  "ghcr.io/craftainer/devcontainer-features/cli-opencode"
]
```

## Corporate CAs at run time

opencode is a single [Bun](https://bun.com) executable, with its own
bundled root CAs. Its [network](https://opencode.ai/docs/network/#custom-certificates)
docs name `NODE_EXTRA_CA_CERTS` for trusting a custom CA ("This works for
both proxy connections and direct API access"). Bun also honours
`NODE_USE_SYSTEM_CA=1`, which adds the operating system's trust store, and
`SSL_CERT_FILE` / `SSL_CERT_DIR`, which add CA certificates on top of the
bundled ones
([Bun environment variables](https://bun.com/docs/runtime/env)). `ssl-ca`
sets all four in `containerEnv`: `NODE_EXTRA_CA_CERTS` and `SSL_CERT_FILE`
to the system bundle `/etc/ssl/certs/ca-certificates.crt` it updates,
`SSL_CERT_DIR` to `/etc/ssl/certs`, and `NODE_USE_SYSTEM_CA` to `1` (the
full list of twelve is in its NOTES.md). So a root CA it installs is
trusted with no further setting. Without `ssl-ca`, set
`NODE_EXTRA_CA_CERTS` to your CA's PEM file in `containerEnv`.

opencode's TUI talks to a local HTTP server, so if you set `HTTPS_PROXY`
or `HTTP_PROXY`, also set `NO_PROXY=localhost,127.0.0.1` (same page).

## OS support

Debian and Ubuntu (glibc), on amd64 and arm64. The x64 build needs a CPU
with AVX2. The install adds `curl` and `ca-certificates` if either is
missing.

## License

opencode is MIT-licensed ([LICENSE](https://github.com/anomalyco/opencode/blob/dev/LICENSE)). Its release tarball holds only the binary, so the feature installs no license file.
