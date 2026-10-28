# 0004. Create one GitHub Release for the collection per publish

## Status

Accepted. Amends [0001](0001-one-collection-repo-released-with-devcontainers-action.md)'s
"no repo-wide tag".

## Context

[ADR 0001](0001-one-collection-repo-released-with-devcontainers-action.md)
versions each feature on its own and publishes it with
`devcontainers/action`, which tags each published version
`<id>_v<version>` and creates no GitHub Release. ADR 0001 also says this
repo isn't released through a repo-wide tag.

That leaves the repo without a Releases page: nothing shows which
feature versions shipped together, when, or what changed in one publish,
and nobody can watch the repo for releases. Per-feature OCI versions
remain what consumers pin; they don't need a collection version to use a
feature.

Base's `release.yml` can't produce such a release: it's manually
dispatched, takes the bump as an input, and builds through the
`Makefile` contract, which stays a no-op here (ADR 0001). The bump that
matters is already encoded in the features' own versions, so it can be
derived rather than chosen by hand.

## Decision

We will create one GitHub Release for the whole collection after each
successful publish on `main` that changed a feature version, from a
`release` job in `features.yml` (not from base's `release.yml`, which
stays unused).

- **Tag.** `v<x.y.z>` on the published commit. The previous release is
  the highest `v<x.y.z>` tag in that commit's history (tags elsewhere are
  ignored); the first release is `v1.0.0`.
- **Bump.** Each `src/<id>/devcontainer-feature.json` `version` is
  compared with the previous release tag. Any feature major bump, or a
  removed feature, bumps major; otherwise a minor bump or a new feature
  bumps minor; otherwise a patch bump bumps patch. With no version change
  there's no release.
- **Notes.** Every feature as `id@version`, linked to its `src/<id>/` at
  the tag, with the changed ones marked (new, or old → new), the removed
  ones listed, and how to reference a feature
  (`ghcr.io/craftainer/devcontainer-features/<id>:<major>`).
- **Re-runs are safe.** A release tag already on HEAD is reused, and
  the job skips when its release exists (or creates it when only the tag
  does). No release when a later release already contains HEAD (a re-run
  of an older push). The computed tag existing outside HEAD's history
  fails the job rather than collide.

The rules live in `scripts/collection-release.sh`, tested by
`scripts/test-collection-release.sh` (a prek hook, so CI runs it). The
job has `contents: write` only and uses the workflow's `GITHUB_TOKEN`.

## Consequences

- The repo gets a Releases page and a changelog per publish, and the
  collection version signals the largest change in it: a major collection
  release means some feature broke compatibility or was removed.
- Consumers still pin per-feature OCI versions. The collection tag isn't
  a consumer contract, and the notes say so.
- A publish that changed no version (e.g. a docs-only push) makes no
  release, and a failed publish makes none either; the next successful
  publish's release covers everything since the previous tag. That
  includes a publish whose packages went out but whose README PR step
  failed (the release needs the whole publish job to succeed); the
  pre-flight lets Actions create PRs, so that step isn't expected to
  fail. The same holds when a quick third push cancels a second push's
  pending release job.
- A release created with `GITHUB_TOKEN` doesn't trigger other workflows
  (`release: published`), which nothing here needs.
- Base's release convention (one way to cut a release, through
  `release.yml`) doesn't hold in this instance: the collection release
  comes from `features.yml`, and `release.yml` is never run here.
- If a feature's version ever went down, the release job fails rather
  than guess a bump; `scripts/check-version-bump.sh` prevents that on
  pull requests.
