# devcontainer-features

> [!NOTE]
> This repository is vibe coded with [Claude](https://claude.com/product/claude-code).

craftainer's collection of
[Dev Container Features](https://containers.dev/implementors/features/),
published to `ghcr.io/craftainer/devcontainer-features/<id>`. Each feature
is versioned on its own (see
[ADR 0001](docs/adrs/0001-one-collection-repo-released-with-devcontainers-action.md)).

- **CLI features** (`cli-*`) install a command-line tool at an exact
  version you pin. A downloaded artifact is checked against a sha256 you
  supply; the two apt-installed CLIs trust the repository's signature,
  with a third-party repository's signing key pinned in the feature (see
  [Verification](#verification)).
- **Enterprise features** adapt a devcontainer to a corporate network,
  starting with `ssl-ca` for custom root CAs.

A CLI feature takes its pin from, in order: the feature option, an
`<ID>_*` environment variable in your base image, or a pins file in your
base image. There are no bundled defaults: without a pin the install
fails.

## Features

Reference a feature as `ghcr.io/craftainer/devcontainer-features/<id>:1`.
Each feature's NOTES.md has the full usage; after each full release,
`devcontainers/action` turns it into `src/<id>/README.md`.

| Feature | Installs | Pin inputs | State dirs | Docs |
| --- | --- | --- | --- | --- |
| `cli-keycloak` | `kcadm`: `flavor` `official` (Keycloak's `kcadm.sh` plus a headless JRE) or `rest` (a curl wrapper around the Admin REST API, different syntax) | `official`: version plus one `sha256` (the tarball is the same on every arch); `rest`: none | none | [NOTES](src/cli-keycloak/NOTES.md) |
| `cli-s5cmd` | `s5cmd` | version plus `sha256_amd64` / `sha256_arm64` | none | [NOTES](src/cli-s5cmd/NOTES.md) |
| `cli-rustfs` | RustFS's `rc`, from the upstream `.deb` | version plus `sha256_amd64` / `sha256_arm64` | none | [NOTES](src/cli-rustfs/NOTES.md) |
| `cli-postgres-client` | `psql`, `pg_dump`, `pg_restore` and the other client tools from PGDG | version only, via apt | none | [NOTES](src/cli-postgres-client/NOTES.md) |
| `cli-valkey` | `valkey-cli`, from upstream's binary release | version plus `sha256_amd64` / `sha256_arm64` | none | [NOTES](src/cli-valkey/NOTES.md) |
| `cli-mosquitto` | `mosquitto_pub`, `mosquitto_sub`, `mosquitto_rr` (repo.mosquitto.org on Debian, the distro archive on Ubuntu) | version only, via apt | none | [NOTES](src/cli-mosquitto/NOTES.md) |
| `cli-claude-code` | Anthropic's native `claude` binary, auto-updater and manual updates off | version plus `sha256_amd64` / `sha256_arm64` | `~/.claude` | [NOTES](src/cli-claude-code/NOTES.md) |
| `cli-opencode` | `opencode` (anomalyco/opencode), update checks off | version plus `sha256_amd64` / `sha256_arm64` | `~/.config/opencode`, `~/.local/share/opencode` | [NOTES](src/cli-opencode/NOTES.md) |
| `ssl-ca` | custom root CAs into the system trust store and every JDK `cacerts`, plus the per-tool CA variables | `certs` (inline PEM) and/or `urls` with one sha256 each in `sha256s` | none | [NOTES](src/ssl-ca/NOTES.md) |

Every feature also takes a `pins_file` option (see below).

A download feature also installs upstream's license notice, from the same
verified artifact, under `/usr/local/share/doc/<tool>/` when the artifact
ships one; each NOTES.md has a License section.

### Pin channels

Each feature resolves its pin from the first of these that sets it
(`ssl-ca` resolves `certs` and the `urls`/`sha256s` pair separately,
each from its own first channel):

1. **The feature option**: `version`, plus `sha256_amd64` and
   `sha256_arm64` (or `sha256` for an arch-independent artifact).
2. **An `<ID>_*` environment variable in your image**, from an `ENV` line
   in the Dockerfile your devcontainer builds from.
3. **A pins file in your image**, `/etc/devcontainer-features/pins.env`
   unless the `pins_file` option names another path. It holds the same
   `KEY=value` lines and is parsed, never sourced. One file can hold the
   pins of every feature; each reads only its own keys.
4. **Otherwise the install fails**, naming all three channels. There are
   no bundled defaults.

A version and its sha always come from the same channel: one channel that
sets only half of a pin fails, rather than borrowing the rest from a later
channel.

**Naming rule:** `<ID>` is the feature id upper-cased, with `-` turned
into `_`, and every pin variable is `<ID>_<OPTION>`. So `cli-rustfs`'s
`sha256_amd64` is `CLI_RUSTFS_SHA256_AMD64`, `cli-keycloak`'s `flavor` is
`CLI_KEYCLOAK_FLAVOR`, and `ssl-ca`'s `urls` is `SSL_CA_URLS`. The other
options, `pins_file` and `cli-keycloak`'s `install_jre`, are read only
from the feature option.

An option, fed from the host with `${localEnv:...}`:

```jsonc
"features": {
  "ghcr.io/craftainer/devcontainer-features/cli-rustfs:1": {
    "version": "${localEnv:CLI_RUSTFS_VERSION}",
    "sha256_amd64": "${localEnv:CLI_RUSTFS_SHA256_AMD64}",
    "sha256_arm64": "${localEnv:CLI_RUSTFS_SHA256_ARM64}"
  },
  "ghcr.io/craftainer/devcontainer-features/cli-postgres-client:1": {
    "version": "${localEnv:CLI_POSTGRES_CLIENT_VERSION}"
  }
}
```

An `ENV` in your Dockerfile, with the feature's options left empty:

```dockerfile
ENV CLI_RUSTFS_VERSION=0.1.36
ENV CLI_RUSTFS_SHA256_AMD64=2eb2d646b04206112c44d65ad5107edf1d164fc93f705c978397bc11eb29a95f
ENV CLI_RUSTFS_SHA256_ARM64=c5ad321059d6478994ee7f07abe131b81def0a09352f08df6eb982c612659ccb
ENV CLI_POSTGRES_CLIENT_VERSION=18.6
```

A pins file, copied into the image:

```sh
# pins.env
CLI_RUSTFS_VERSION=0.1.36
CLI_RUSTFS_SHA256_AMD64=2eb2d646b04206112c44d65ad5107edf1d164fc93f705c978397bc11eb29a95f
CLI_RUSTFS_SHA256_ARM64=c5ad321059d6478994ee7f07abe131b81def0a09352f08df6eb982c612659ccb
CLI_POSTGRES_CLIENT_VERSION=18.6
```

```dockerfile
COPY pins.env /etc/devcontainer-features/pins.env
```

The details are in
[ADR 0002](docs/adrs/0002-resolve-pins-from-option-env-or-pins-file-with-no-defaults.md).

### Verification

- **Download features** (`cli-keycloak` `official`, `cli-s5cmd`,
  `cli-rustfs`, `cli-valkey`, `cli-claude-code`, `cli-opencode`, and
  `ssl-ca`'s `urls`) check every download against the sha256 you supply:
  one per arch, or a single one for an artifact that is the same on every
  arch (the Keycloak tarball, a CA certificate). The feature never fetches
  upstream's checksum file, so the sha you review is the one that counts.
  A mismatch deletes the download and fails the install.
- **apt features** (`cli-postgres-client`, `cli-mosquitto`) take a version
  only. apt checks every package against the repository's signed index,
  and the feature pins the third-party repository's signing key by a
  fingerprint constant (PGDG, and repo.mosquitto.org on Debian). The
  version is the upstream one (`18.6`, `2.0.22`), not the Debian package
  version; when the sources carry several Debian revisions of it, the
  highest is installed. See
  [ADR 0003](docs/adrs/0003-pin-apt-installed-clis-by-upstream-version-with-a-verified-repo-key.md).

### State and credentials

**A feature declares `mounts` only when its tool can't run without one**,
and none in this collection does. A feature's mounts can't be switched off
by an option, and where credentials live is your security choice. No
feature sets a state-path variable such as `CLAUDE_CONFIG_DIR` either.

- **`cli-claude-code` and `cli-opencode`** create their state directories
  in the remote user's home, owned by that user with mode `0700`, so a
  named volume you mount there starts out writable. Claude Code also
  keeps `~/.claude.json` outside `~/.claude`, so a volume on `~/.claude`
  alone doesn't keep the login; see its NOTES.md. Their NOTES.md give
  three options: a volume per project, one volume shared by all projects,
  or no volume and a token or API key passed in from the host (the
  recommended option for enterprise use).
- **The other CLIs** keep no state; pass credentials in from the host
  (`${localEnv:...}` in `containerEnv`, or a Compose `env_file`) rather
  than baking them into the image:

  | Feature | Credentials |
  | --- | --- |
  | `cli-keycloak` | `KEYCLOAK_URL`, `KEYCLOAK_ADMIN`, `KEYCLOAK_ADMIN_PASSWORD` (read by `rest`); for `official`, pass them to `kcadm.sh config credentials`, with the password in `KC_CLI_PASSWORD` |
  | `cli-s5cmd` | `AWS_*` and `S3_ENDPOINT_URL` |
  | `cli-rustfs` | an alias from `rc alias set` in a `postCreateCommand`; `rc` ignores `AWS_*`. A keyed `rc alias set` checks the keys against the endpoint, so the S3 service must be reachable when the command runs |
  | `cli-postgres-client` | libpq's `PG*` variables (`PGHOST`, `PGUSER`, `PGPASSWORD` or `PGPASSFILE`, ...) |
  | `cli-valkey` | `VALKEYCLI_AUTH`, or `REDISCLI_AUTH` |
  | `cli-mosquitto` | `-u` / `-P` on the command line, or each client's own config file (`~/.config/mosquitto_pub` and so on) to keep the password out of `ps` |

### Install order

No feature here declares `installsAfter`: the Dev Container CLI fetches
every `installsAfter` reference from ghcr.io and fails when it can't,
which would break offline and proxied builds even for consumers who don't
use the referenced feature. Set the order yourself with
`overrideFeatureInstallOrder`:

- list `ssl-ca` first, so your CA is trusted before any other feature
  downloads something;
- list a feature that creates the remote user, such as `common-utils`,
  before `cli-claude-code` and `cli-opencode`, whose install fails if the
  remote user's home doesn't exist yet.

```jsonc
"features": {
  "ghcr.io/devcontainers/features/common-utils:2": {},
  "ghcr.io/craftainer/devcontainer-features/ssl-ca:1": {
    "certs": "${localEnv:CORP_CA_PEM}"
  },
  "ghcr.io/craftainer/devcontainer-features/cli-claude-code:1": {}
},
"overrideFeatureInstallOrder": [
  "ghcr.io/craftainer/devcontainer-features/ssl-ca",
  "ghcr.io/devcontainers/features/common-utils",
  "ghcr.io/craftainer/devcontainer-features/cli-claude-code"
]
```

### AWS CLI

This collection doesn't ship the AWS CLI. Use the official
[`ghcr.io/devcontainers/features/aws-cli`](https://github.com/devcontainers/features/tree/main/src/aws-cli)
feature, which verifies its download with AWS's GPG signature.

### Supported platforms

Debian 13 and Ubuntu 24.04, including the
`mcr.microsoft.com/devcontainers/base` images built on them, on amd64 and
arm64. Alpine and other musl-based images aren't supported. Per-feature
caveats:

- `cli-valkey` uses upstream's Ubuntu 24.04 build, which needs glibc 2.38
  or later and OpenSSL 3.
- `cli-opencode`'s x64 build needs a CPU with AVX2.
- `cli-keycloak`'s `official` flavor needs Java 21 or newer, installed by
  default (`install_jre`).
- `cli-mosquitto`'s available versions differ per distro, so a pin is
  distro-specific.
- `cli-rustfs` installs `/usr/bin/rc`, which clashes with Debian's `rc`
  (Plan 9 shell) package.

## Working on features

There is deliberately no `src/README.md`: `devcontainers/action`
validates every entry under `src/` as a feature folder, so a plain file
there fails validation. The rules for `src/` live here
instead; [`common/README.md`](common/README.md) covers the shared install
library and [`test/README.md`](test/README.md) the scenario tests.

- **Layout.** Each feature is `src/<id>/`: `devcontainer-feature.json`,
  `install.sh`, `NOTES.md` and a copy of the shared library as
  `install-lib.sh`. `src/<id>/README.md` is generated after each full
  release from the metadata and NOTES.md; don't write it by hand.
- **`devcontainer-feature.json`.** Every pin option (`version`, the sha
  options, `pins_file`, `ssl-ca`'s `certs`, `urls` and `sha256s`) has
  `"default": ""`, and a feature with `version` also declares
  `pins_file` (enforced by `scripts/check-feature-options.sh`). No feature
  declares `installsAfter` or `mounts` (see
  [Install order](#install-order) and
  [State and credentials](#state-and-credentials)).
- **The shared library.** `install.sh` sources its own copy with the
  literal line `. "$(dirname "$0")/install-lib.sh"` (after
  `# shellcheck source=install-lib.sh`), which the drift hook looks for.
  Never edit a copy: change `common/install-lib.sh` and re-copy it (see
  [`common/README.md`](common/README.md)).
- **Adding a feature.** Copy `src/cli-s5cmd/` and `test/cli-s5cmd/` to the
  new id, run `cp common/install-lib.sh src/<id>/install-lib.sh`, and
  adapt the metadata, `install.sh`, NOTES.md and scenarios.
- **Bump the version on every change.** A release never republishes a
  feature version already in the registry, so a change under `src/<id>/`
  ships, at the next full release, only when that feature's `version`
  goes up
  ([ADR 0001](docs/adrs/0001-one-collection-repo-released-with-devcontainers-action.md));
  `scripts/check-version-bump.sh` checks it against `origin/main`.
- **`.github/workflows/features.yml`.** On pull requests it validates every
  `devcontainer-feature.json` with `devcontainers/action` and enforces the
  version bump with full history. On pull requests and `main` it runs each
  feature's scenarios on four base images, natively on amd64 and arm64,
  plus the `_global` scenarios (see [`test/README.md`](test/README.md)).
  Merging to `main` only tests; nothing is published. After a full
  release (below), its `docs` job opens a PR with the regenerated
  `src/<id>/README.md` files.
- **Checks.** `prek run --all-files --hook-stage manual` runs shellcheck
  and the hooks in `scripts/` (install-lib drift, feature options, version
  bump).

## Releasing the collection

Releases are cut like in every craftainer repo: dispatch the **Release**
workflow (`release.yml`, from base) on `main` with a `release_type`
(`alpha`, `beta`, `rc` or `full`) and a `bump` (`major`, `minor`, `patch`
or `none`). It tags the collection `v<x.y.z>` (with `-alpha.N` and so on
for a pre-release) and runs this repo's `Makefile` targets, which call
`scripts/release-features.sh`
([ADR 0004](docs/adrs/0004-collection-github-releases.md)):

- `make build` / `make release-assets` package every feature into `dist/`
  (`devcontainer-feature-<id>.tgz` and `devcontainer-collection.json`),
  attached to the GitHub Release on every channel.
- `make publish` pushes the features to
  `ghcr.io/craftainer/devcontainer-features/<id>` with
  `devcontainer features publish`, **only for a `full` release**. alpha,
  beta and rc releases push nothing, so consumers never resolve a
  pre-release. Feature versions already in the registry are skipped.
- `make release-check` (in the devcontainer) validates every
  `devcontainer-feature.json` and checks `dist/` against `src/`.
  `make publish` runs the same checks first, since it runs before
  `release-check` and a pushed feature version can't be replaced.

The collection tag versions the release as a whole; pick the bump by the
largest feature change in it. Each feature's own version still comes from
its `devcontainer-feature.json`, and that is what consumers pin, not the
collection tag.

Publishing needs, once, in the repository's Actions settings, only the
`OCI_REGISTRY` variable set to `ghcr.io`; no secrets. `make publish` then
pushes with the release job's `GITHUB_TOKEN` (as `GITHUB_ACTOR`), which
works once template-sync has brought in a base `release.yml` whose `build`
job grants `packages: write`; until then GHCR denies the push and
`make publish` fails
([ADR 0005](docs/adrs/0005-publish-to-ghcr-with-github-token.md)).
`OCI_IMAGE_NAME` is optional and defaults to
`craftainer/devcontainer-features`. The `OCI_REGISTRY_USERNAME` and
`OCI_REGISTRY_PASSWORD` secrets, when set, take precedence (both are then
required), and are needed for any registry other than `ghcr.io`; to move
`ghcr.io` from them to `GITHUB_TOKEN`, delete both. A feature package that
already exists on GHCR and wasn't first pushed by this repository's
workflow needs, once, this repository given the Write role under the
package's "Manage Actions access" settings, or GHCR denies the push. Without
`OCI_REGISTRY`, a full release publishes nothing and warns.

To try the targets locally: `make build release-assets release-check`;
`RELEASE_TAG=v1.0.0-rc.1 make publish` shows the pre-release skip.

This repo is an instance of
[`template-base`](https://github.com/craftainer/template-base). See
[`docs/TEMPLATE.md`](docs/TEMPLATE.md) for its devcontainer, checks and
template sync.

## License

Licensed under the [GNU General Public License v3.0](LICENSE).
