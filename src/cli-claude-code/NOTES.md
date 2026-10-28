## What it installs

Anthropic's native `claude` binary, the same file the official installer
(`https://claude.ai/install.sh`) downloads, as `/usr/local/bin/claude`. It
needs no Node.js. The feature:

- downloads
  `https://downloads.claude.ai/claude-code-releases/<version>/linux-{x64,arm64}/claude`
  (the glibc builds; Alpine and the bucket's `linux-*-musl` builds are out
  of scope) and checks it against your sha256;
- creates `~/.claude` for the remote user, mode `0700` (see
  [Keeping the login across rebuilds](#keeping-the-login-across-rebuilds));
- sets `DISABLE_AUTOUPDATER=1` and `DISABLE_UPDATES=1` in the container
  environment, so Claude Code doesn't update itself away from your pin
  (see [Bumping the version](#bumping-the-version)).

It declares no mounts and doesn't set `CLAUDE_CONFIG_DIR`: where Claude
Code's state and credentials live is your choice, not the feature's.

## Pinning the version

This feature has no default version. You choose the Claude Code release
and supply the sha256 of its binary for each arch you build on, and the
install fails unless it finds both. The download is always checked against
your sha256; the feature never fetches Anthropic's manifest itself, so the
sha you review is the one that counts.

Each release publishes a `manifest.json` with the sha256 of every platform
binary, under `platforms.<platform>.checksum`:

```sh
VERSION=2.1.312
curl -fsSL "https://downloads.claude.ai/claude-code-releases/${VERSION}/manifest.json" \
  | jq -r '.platforms["linux-x64"].checksum, .platforms["linux-arm64"].checksum'
```

| Arch | Manifest key | Binary |
| --- | --- | --- |
| amd64 | `platforms.linux-x64.checksum` | `<version>/linux-x64/claude` |
| arm64 | `platforms.linux-arm64.checksum` | `<version>/linux-arm64/claude` |

The manifest is signed with Anthropic's release key from `2.1.89` on; to
check the signature before you trust the shas, follow
[Binary integrity and code signing](https://code.claude.com/docs/en/setup#binary-integrity-and-code-signing).
The version is the plain release number (`2.1.312`), the same as the npm
package `@anthropic-ai/claude-code`. You only need the sha for the arches
you actually build on.

The pin can come from three places. The feature uses the first one that
sets either the version or a sha, and that place must set both: a version
in one place is never paired with a sha from another.

### 1. Feature options

```jsonc
"features": {
  "ghcr.io/craftainer/devcontainer-features/cli-claude-code:1": {
    "version": "2.1.312",
    "sha256_amd64": "4f4178ce41d83e23341ebfbaecdbcf8ea6bf7baea0690025abe49eeec3a5d01d",
    "sha256_arm64": "dc4af28917455e009d26704b82a438353a06149e825b6cdf782908b2d28661f5"
  }
}
```

To keep the pin out of `devcontainer.json`, feed the options from the
host's environment:

```jsonc
"ghcr.io/craftainer/devcontainer-features/cli-claude-code:1": {
  "version": "${localEnv:CLI_CLAUDE_CODE_VERSION}",
  "sha256_amd64": "${localEnv:CLI_CLAUDE_CODE_SHA256_AMD64}",
  "sha256_arm64": "${localEnv:CLI_CLAUDE_CODE_SHA256_ARM64}"
}
```

### 2. Environment variables in your image

Set `CLI_CLAUDE_CODE_VERSION`, `CLI_CLAUDE_CODE_SHA256_AMD64` and
`CLI_CLAUDE_CODE_SHA256_ARM64` with `ENV` in the Dockerfile your
devcontainer builds from, and leave the feature's options empty:

```dockerfile
ENV CLI_CLAUDE_CODE_VERSION=2.1.312
ENV CLI_CLAUDE_CODE_SHA256_AMD64=4f4178ce41d83e23341ebfbaecdbcf8ea6bf7baea0690025abe49eeec3a5d01d
ENV CLI_CLAUDE_CODE_SHA256_ARM64=dc4af28917455e009d26704b82a438353a06149e825b6cdf782908b2d28661f5
```

```jsonc
"build": { "dockerfile": "Dockerfile" },
"features": {
  "ghcr.io/craftainer/devcontainer-features/cli-claude-code:1": {}
}
```

### 3. A pins file in your image

Put the same `KEY=value` lines in a file and `COPY` it into the image at
`/etc/devcontainer-features/pins.env`. One file can hold the pins of every
feature in this collection; each feature reads only its own keys.

```sh
# pins.env
CLI_CLAUDE_CODE_VERSION=2.1.312
CLI_CLAUDE_CODE_SHA256_AMD64=4f4178ce41d83e23341ebfbaecdbcf8ea6bf7baea0690025abe49eeec3a5d01d
CLI_CLAUDE_CODE_SHA256_ARM64=dc4af28917455e009d26704b82a438353a06149e825b6cdf782908b2d28661f5
```

```dockerfile
COPY pins.env /etc/devcontainer-features/pins.env
```

The file is parsed, never sourced: `KEY=value` lines (optionally after
`export`), `#` comments and quoted values are understood, and nothing is
expanded. To keep it somewhere else, set the `pins_file` option to its
path in the image:

```jsonc
"ghcr.io/craftainer/devcontainer-features/cli-claude-code:1": {
  "pins_file": "/opt/pins/devcontainer.env"
}
```

## Bumping the version

Claude Code normally updates itself in the background. This feature sets
two of Anthropic's documented switches in `containerEnv`
([environment variables](https://code.claude.com/docs/en/env-vars)), so
the version you pinned is the version that runs:

- `DISABLE_AUTOUPDATER=1` stops the background updater;
- `DISABLE_UPDATES=1` also blocks the manual `claude update` and
  `claude install`. Those manage the native installer's own per-user
  layout (versions under `~/.local/share/claude/versions/`, a launcher at
  `~/.local/bin/claude`), not this feature's `/usr/local/bin/claude`, so
  they would leave a second copy that shadows the pinned one wherever
  `~/.local/bin` comes first on `PATH`.

To move to a newer release, change the pin: put the new version and its
two shas from that release's `manifest.json` wherever you set the pin,
and rebuild the container.

## Keeping the login across rebuilds

Claude Code keeps its credentials, settings and session history in
`~/.claude`, and its account details, MCP servers and per-project trust in
`~/.claude.json`, outside that directory unless `CLAUDE_CONFIG_DIR` says
otherwise. A rebuild discards both, so you sign in again each time unless
you choose one of the options below. Anthropic's own guidance is on
[Development containers](https://code.claude.com/docs/en/devcontainer).

The feature declares no mount: a feature's mounts can't be switched off,
and whether credentials sit in a volume, and whether projects share one,
is a security choice that belongs to you. What it does is create
`~/.claude` in the image, owned by the remote user with mode `0700`.
Docker seeds an empty named volume with the ownership of the directory it
is mounted on, so a volume you mount there starts out writable by the
remote user instead of owned by root.

In the snippets below, replace `/home/vscode` with your `remoteUser`'s
home directory (`/root` if the container runs as root).

### (a) One volume per project

Each devcontainer gets its own volume, named after its
`${devcontainerId}`, and `CLAUDE_CONFIG_DIR` puts `.claude.json` inside
it too. A login in one project isn't visible to another. This is the
pattern in Anthropic's
[reference configuration](https://github.com/anthropics/claude-code/blob/main/.devcontainer/devcontainer.json).

```jsonc
"mounts": [
  "source=claude-code-config-${devcontainerId},target=/home/vscode/.claude,type=volume"
],
"containerEnv": {
  "CLAUDE_CONFIG_DIR": "/home/vscode/.claude"
}
```

### (b) One volume shared by all projects

Sign in once and every devcontainer that mounts the same volume is signed
in. The trade-off: every container that mounts it can read the same token,
including a container for a repository you trust less.

```jsonc
"mounts": [
  "source=claude-code-config,target=/home/vscode/.claude,type=volume"
],
"containerEnv": {
  "CLAUDE_CONFIG_DIR": "/home/vscode/.claude"
}
```

### (c) No volume, a token from the host

Keep no credentials in the container at all and pass one in from the
host's environment on every start: either a long-lived
`CLAUDE_CODE_OAUTH_TOKEN`, which you generate once with
`claude setup-token`, or an `ANTHROPIC_API_KEY`. Settings and history
still don't survive a rebuild, but nothing secret is stored in a volume,
and revoking the token on the host side is enough. **This is the
recommended option for enterprise use.**

```jsonc
"containerEnv": {
  "CLAUDE_CODE_OAUTH_TOKEN": "${localEnv:CLAUDE_CODE_OAUTH_TOKEN}"
}
```

or

```jsonc
"containerEnv": {
  "ANTHROPIC_API_KEY": "${localEnv:ANTHROPIC_API_KEY}"
}
```

## Install order

This feature deliberately declares no `installsAfter`: the Dev Container
CLI fetches every `installsAfter` reference from ghcr.io, so declaring one
would make every build reach ghcr.io for features you may not use. Set
the order yourself with `overrideFeatureInstallOrder` in these two cases.

- **`ssl-ca`.** If you use this collection's `ssl-ca` feature for a
  corporate root CA, the CA has to be trusted before Claude Code is
  downloaded, so list `ssl-ca` first.
- **A feature that creates the remote user**, such as
  `ghcr.io/devcontainers/features/common-utils` on an image without that
  user. This feature creates `~/.claude` in the remote user's home, and
  the install fails if that home doesn't exist yet, so list the
  user-creating feature before this one.

```jsonc
"overrideFeatureInstallOrder": [
  "ghcr.io/devcontainers/features/common-utils",
  "ghcr.io/craftainer/devcontainer-features/ssl-ca",
  "ghcr.io/craftainer/devcontainer-features/cli-claude-code"
]
```

## Corporate CAs at run time

`ssl-ca` sets twelve CA variables in `containerEnv` (the full list is in
its NOTES.md): `NODE_EXTRA_CA_CERTS`, `SSL_CERT_FILE` and seven other
per-tool variables point at the system bundle
`/etc/ssl/certs/ca-certificates.crt`, `SSL_CERT_DIR` at `/etc/ssl/certs`,
and `NODE_USE_SYSTEM_CA` and `UV_NATIVE_TLS` are `1`. The one that
matters here is `NODE_EXTRA_CA_CERTS`.

The native binary has no Node.js installation behind it, so `ssl-ca`'s
`NODE_USE_SYSTEM_CA=1` doesn't apply to it. It doesn't need to: per
Anthropic's
[network configuration](https://code.claude.com/docs/en/network-config#ca-certificate-store)
docs, Claude Code trusts both its bundled Mozilla CA set and the operating
system's trust store by default (`CLAUDE_CODE_CERT_STORE=bundled,system`),
and the native binary can always read the system store. A root CA that
`ssl-ca` installs into the system trust store is therefore trusted with no
further setting. Claude Code also honours `NODE_EXTRA_CA_CERTS`, which
`ssl-ca` points at the system bundle, so nothing conflicts. Don't set
`CLAUDE_CODE_CERT_STORE=bundled`, which would drop the system store and
with it your CA.

## OS support

Debian and Ubuntu (glibc), on amd64 and arm64. The install adds
`curl` and `ca-certificates` if either is missing.

## License

Claude Code is proprietary and its binary ships no license file, so the feature installs none; your use is subject to Anthropic's [Commercial Terms of Service](https://www.anthropic.com/legal/commercial-terms) or, on a Free, Pro or Max plan, its [Consumer Terms](https://www.anthropic.com/legal/consumer-terms) (see [Legal and compliance](https://code.claude.com/docs/en/legal-and-compliance)).
