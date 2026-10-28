# 0001. Ship every feature from one collection repo, released with `devcontainers/action`

## Status

Accepted. Amended by [0004](0004-collection-github-releases.md): the
collection is released through base's `release.yml` and `Makefile`
contract under a repo-wide `v<x.y.z>` tag, and a full release publishes
the features with the Dev Container CLI; `features.yml` no longer
publishes on `main`. `devcontainers/action` still validates the features
and generates their READMEs.

## Context

craftainer needs Dev Container Features of two kinds: CLI features that
install a tool at an exact, sha256-verified version (the Keycloak admin
CLI, S3 clients, the PostgreSQL client, `valkey-cli`, the Mosquitto
clients, Claude Code, opencode), and enterprise features that adapt a
devcontainer to a corporate network (custom root CAs first).

Two questions follow: how many repos, and how to release.

- **The spec's unit is a collection.** The
  [features distribution spec](https://containers.dev/implementors/features-distribution/)
  publishes a set of features from one repo under one OCI namespace
  (`ghcr.io/<owner>/<repo>/<id>`), plus a collection metadata package.
  The large public collections, `devcontainers/features`,
  `devcontainers-extra/features` and
  `devcontainer-community/devcontainer-features`, are each a single repo.
  The official [feature-starter](https://github.com/devcontainers/feature-starter)
  lays a collection out as `src/<id>/` and `test/<id>/`.
- **Each feature has its own semver.** A feature's
  `devcontainer-feature.json` `version` is what consumers pin, and
  [`devcontainers/action`](https://github.com/devcontainers/action)
  publishes each one as `X`, `X.Y`, `X.Y.Z` and `latest`. The action never
  republishes a version that already exists, so a change ships only when
  that feature's `version` goes up.
- **This repo is an instance of `template-base`.** Base's `release.yml`
  releases the whole repo from one tag through a `Makefile` contract
  (`build`, `sbom`, `release-assets`, `publish`). A single repo-wide
  version doesn't fit features that each carry their own.
- **The alternatives.** A separate repo for enterprise features would
  mean a second namespace, a second copy of the shared install library
  and its CI, with nothing gained for consumers. A Dev Container Template
  repo ([template-starter](https://github.com/devcontainers/template-starter))
  ships `.devcontainer/` scaffolds that combine features; nothing needs
  one yet, and templates can't be published in the same action run as
  features.

## Decision

We will publish every craftainer Dev Container Feature, CLI and
enterprise alike, from this one repo, `craftainer/devcontainer-features`,
to `ghcr.io/craftainer/devcontainer-features/<id>`, laid out like the
official feature-starter.

We will release features with `devcontainers/action` from an
instance-owned `.github/workflows/features.yml` (validate on pull
requests, test, and publish on `main`), and each feature is versioned on
its own through its `devcontainer-feature.json`. Base's `release.yml` and
`Makefile` targets stay as base's documented no-ops, and this repo isn't
released through a repo-wide tag: base's manually dispatched Release
workflow is never run here.

## Consequences

- Consumers reference one namespace and pin each feature's version on its
  own. A fix to one feature doesn't bump the others.
- Every change under `src/<id>/` must raise that feature's `version`, or
  the publish silently skips it. A prek hook is to enforce this against
  `origin/main`; until it lands, reviewers check it.
- The features share `common/install-lib.sh`, but a feature folder is
  packaged on its own, so each `src/<id>/` carries a verbatim copy of it.
  A prek hook is to fail when a copy drifts; until it lands, reviewers
  check it.
- `features.yml`, `src/`, `test/` and `common/` are instance-owned and
  listed in `.github/template-sync-manifest.local.yml`, so template sync
  never touches them. Base's release tooling still syncs in, unused.
- Each new feature package on GHCR starts private and has to be made
  public by hand once.
- Adding a Dev Container Template later means a separate repo, or a
  separate publish job, and a new ADR.
