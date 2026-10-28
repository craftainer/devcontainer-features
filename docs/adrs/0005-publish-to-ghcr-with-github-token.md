# 0005. Publish to GHCR with the release job's `GITHUB_TOKEN`

## Status

Accepted. Partly supersedes
[0004](0004-collection-github-releases.md).

## Context

[ADR 0004](0004-collection-github-releases.md)'s `publish` authenticates
only with the `OCI_REGISTRY_USERNAME` / `OCI_REGISTRY_PASSWORD` secrets,
which on `ghcr.io` means a classic personal access token with
`write:packages`. It did so because `release.yml`'s `build` job, where
`make publish` runs, had `contents: write` only. A classic token is
long-lived, tied to one person and broader than this repository.

Base's `release.yml` now grants the `build` job `packages: write`, and
GitHub's guidance ("Publishing and installing a package with GitHub
Actions") recommends the job's `GITHUB_TOKEN` over a personal access token
for pushing to the repository's own GHCR packages.

## Decision

We will have `publish` pick its credential this way, still passing it to
the Dev Container CLI only through `DEVCONTAINERS_OCI_AUTH`
(`registry|user|token`) and still rejecting a `|` or `,` in any part of it:

- Either registry secret set: both secrets, as before (one alone fails).
  Explicit secrets always win.
- Neither set and `OCI_REGISTRY` is `ghcr.io`: `GITHUB_TOKEN` as
  `GITHUB_ACTOR`. Without either of them it fails.
- Neither set and any other registry: fails, as before.

`GITHUB_TOKEN` is removed from the CLI's environment either way, so the
only credential it sees is the one chosen here. `OCI_REGISTRY` stays the
opt-in: unset still skips with a warning, a pre-release still pushes
nothing, and only the amd64 leg publishes.

A features-only publish job triggered by `workflow_run` was considered
instead and rejected: it would split this repo's release path from every
other craftainer repo's.

## Consequences

- On GHCR, publishing needs only the `OCI_REGISTRY` variable, once this
  repo's synced `release.yml` carries `packages: write`. Until
  template-sync brings it in, GHCR denies a full release's push when the
  secrets are empty, and `publish` fails naming that cause.
- Moving an existing setup from the secrets to `GITHUB_TOKEN` means
  deleting both secrets; leaving one fails, and leaving both keeps using
  them.
- A feature package that already exists and wasn't first pushed by this
  repository's workflow needs, once, this repository given the Write role
  under the package's "Manage Actions access" settings, or GHCR denies the
  push.
- Any other registry still needs both secrets.
