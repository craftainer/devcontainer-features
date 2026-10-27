# 0003. Pin apt-installed CLIs by upstream version, with a verified repository key

## Status

Accepted. Partly supersedes
[0002](0002-resolve-pins-from-option-env-or-pins-file-with-no-defaults.md).

## Context

[ADR 0002](0002-resolve-pins-from-option-env-or-pins-file-with-no-defaults.md)
requires every CLI feature to install an exact version checked against a
consumer-supplied sha256. That works for a downloaded artifact. Two
features install from apt: `cli-postgres-client` (`psql` from PGDG) and
`cli-mosquitto` (`mosquitto-clients`). For these, a consumer sha doesn't
fit:

- **The `.deb` differs per distro and arch.** PGDG builds
  `18.6-1.pgdg13+2` for Debian 13 and `18.6-1.pgdg24.04+2` for Ubuntu
  24.04, each per arch, and dependencies such as `libpq5` come from the
  same repository. A sha pin would mean a set of shas per distro, arch and
  dependency, and Renovate can't compute any of them.
- **apt already checks integrity.** Every package is checked against the
  repository's signed `InRelease`. What has to be trusted is the signing
  key. The official devcontainers features (`docker-in-docker`,
  `aws-cli`) pin that key by a fingerprint constant in the feature. The
  constant is a trust anchor, not a version pin, so it isn't a bundled
  default.
- **Revisions differ per distro, upstream versions don't.** A consumer
  matching the stack's Postgres 18.6 thinks "18.6", not
  `18.6-1.pgdg13+2`.
- **Per-distro sources.** repo.mosquitto.org carries exact 2.0.x and 2.1.x
  builds for Debian. Ubuntu 24.04's own archive has only 2.0.18.
- **apt pins only the named package.** `apt-get install
  mosquitto-clients=2.0.22-…` fails once 2.1.x is in the repository:
  `mosquitto-clients` Depends on `libmosquitto1 (= 2.0.22-…)`, and apt keeps
  the newest `libmosquitto1` as its candidate.
- **Bare images lack the tools.** `debian:13` and `ubuntu:24.04` ship
  without `curl`, `ca-certificates` and `gpg`. Both have a signature
  verifier (`sqv` or `gpgv`), but those only verify signatures. They can't
  print a key's fingerprint or unarmor a key.
- **Two gaps in 0002's implementation** (found reviewing `cli-s5cmd`):
  - `il_resolve_pin` detected a channel only by the version or the current
    arch's sha. A channel that set only the other arch's sha was skipped,
    and a later channel was used instead. 0002 says a channel that sets
    either value is used, and never completed from a later channel.
  - `il_fetch_verified` installed `ca-certificates` only when `curl` was
    missing. An image with curl but no CA bundle failed every https fetch
    with a TLS error.
- The G5 gate in the collection's plan settled this: the user chose
  version-only pins for these features, given as the upstream version.

## Decision

**Version-only pins for apt-installed CLIs.** `cli-postgres-client` and
`cli-mosquitto` take a version and no sha. Every download-based feature
keeps 0002's version plus sha unchanged. `il_resolve_version <ID>`
resolves the version through 0002's channels and order: the `version`
option, then `<ID>_VERSION` in the image environment, then the pins file.
The first channel that sets it wins. With none, the install fails naming
all three channels. These features declare `version` and `pins_file`
with `"default": ""`, as 0002 requires.

**The version is the upstream version.** It must be digits and dots
(`18.6`, `2.0.22`), with no leading `v`, no epoch and no distro revision.
It is checked before it is logged or reaches apt.
`il_apt_install_pinned <pkg> <version>`:

1. runs `apt-get update`;
2. reads `apt-cache madison <pkg>` and takes the candidates whose version
   is exactly `<version>-<revision>`, optionally with an epoch `N:`;
3. installs exactly one with `--no-install-recommends`. None, or several,
   fails and lists the versions available.

The revision isn't pinned, so one pin works on every distro the
repository builds for.

**Exact-version dependencies are pinned with the package.** Every
unconditional `name (= version)` entry in the chosen version's `Depends`
and `Pre-Depends` is added as `name=version` to the same `apt-get
install`, transitively. An entry inside an `a | b` alternative is left to
apt, and so is a `>=` or `<<` entry. An arch qualifier `:any` or `:native`
is dropped, so the native package is pinned; any other qualifier is kept.
Two different exact versions required for one package fail the install.
Afterwards the pinned dependencies are marked automatically installed,
unless they were already installed manually, so only `<pkg>` stays
manual. The apt lists are removed, as `il_apt_install` does.

**A third-party repository is trusted through a fingerprint constant.**
`il_apt_add_repo <name> <key_url> <fingerprint> <source_line>`:

1. fetches the key over https only;
2. unarmors it if it is armored (PGDG's is, mosquitto's is binary);
3. checks with `gpg --show-keys` that the exact bytes apt will trust hold
   one primary key, and that its fingerprint is `<fingerprint>` (40 hex
   digits, spaces and case ignored). A second primary key fails too,
   since apt would trust it as well;
4. installs the key as `/etc/apt/keyrings/<name>.gpg` (mode 0644) and
   writes `/etc/apt/sources.list.d/<name>.list` as `deb
   [signed-by=/etc/apt/keyrings/<name>.gpg] <source_line>`;
5. runs `apt-get update --error-on=any` for that list alone, so a wrong
   suite, an unreachable host or a bad signature fails here, not later as
   a missing package.

On a mismatch, nothing is written. On any later failure, the key and the
list are removed. The constants are PGDG
`B97B0AFCAA1A47F044F244A07FCC7D46ACCC4CF8` and repo.mosquitto.org
`8277CCB49EC5B595F2D2C71361611AE430993623`. `cli-mosquitto` adds
repo.mosquitto.org on Debian only. On Ubuntu it installs from the
distro's own archive.

**gpg is installed on demand.** When `gpg` is missing, the `gpg` package
is installed with `--no-install-recommends`. That is the minimal OpenPGP
tool that can both show a fingerprint and unarmor a key; `sqv` and `gpgv`
can't. It runs with a throwaway `GNUPGHOME`, so no `~/.gnupg` is left
behind. gpg itself stays installed, as in the official features: removing
it with `--auto-remove` could also remove unrelated automatically
installed packages.

**When a channel is set (refines 0002).** For `il_resolve_pin`, a channel
counts as set when it sets the version or any of its sha keys. For an
arch-specific feature that includes both `_AMD64` and `_ARM64`; for an
arch-independent one, `SHA256`. A set channel must supply the version and
this arch's sha. Otherwise the install fails naming what is missing, for
example "the feature options set sha256_arm64 but not version or
sha256_amd64 (this machine is amd64)". It never falls through to a later
channel. The rule is the same for options, the image environment and the
pins file. `il_resolve_pin` also rejects a version with a leading `v` or
`V` before logging it as resolved. A release tag that has a `v` gets it
added by the feature.

**curl and the CA bundle are each installed when missing.** Every https
fetch (`il_fetch_verified`, and the key fetch in `il_apt_add_repo`) first
installs `curl` if there is no `curl` command, and `ca-certificates` if
`/etc/ssl/certs/ca-certificates.crt` is missing. The retry message counts
real curl calls ("call 2/4").

## Consequences

- `cli-postgres-client` and `cli-mosquitto` give weaker integrity than the
  download features: the consumer pins what is installed, but trusts the
  repository's signing key for the bytes. The key itself is pinned in the
  feature, so a substituted key fails the install.
- One pin (`18.6`) works on Debian and Ubuntu, amd64 and arm64. When the
  repository publishes two revisions of the same upstream version, the
  install fails until one of them is gone, rather than guessing.
- A repository can drop an old version. The pin then fails with the list
  of what's available, the same way a deleted download fails a sha pin.
- Mosquitto's available versions differ by distro, so `cli-mosquitto`'s
  tests and documentation pick the pin per distro.
- A rotated repository key needs a new feature release with the new
  fingerprint.
- The image keeps `gpg`, plus `curl` and `ca-certificates`, when the
  feature had to install them.
- A consumer whose channel sets only the other arch's sha now gets an
  error instead of a pin silently read from a later channel. That is
  0002's intent, now enforced.
