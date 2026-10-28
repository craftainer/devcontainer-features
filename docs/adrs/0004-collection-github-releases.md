# 0004. Release the collection through base's `release.yml`

## Status

Accepted. Amends [0001](0001-one-collection-repo-released-with-devcontainers-action.md):
features are published by base's `release.yml` through the `Makefile`
contract, on a full collection release, not by `devcontainers/action` on
every push to `main`. Amended 2026-10-28 (see "Amendment: publish to GHCR
with `GITHUB_TOKEN`" below): on `ghcr.io`, `publish` authenticates with the
job's `GITHUB_TOKEN` when the registry secrets are empty.

## Context

[ADR 0001](0001-one-collection-repo-released-with-devcontainers-action.md)
versions each feature on its own and originally published every new
feature version from `features.yml` on each push to `main`, with no
repo-wide tag. That left the repo without a Releases page, and it made
this repo the one craftainer instance that isn't released the way every
other one is: by dispatching base's synced `release.yml` with a
`release_type` (`alpha`, `beta`, `rc`, `full`) and a `bump`.

`release.yml` stays byte-identical to base (template sync owns it). It
computes the next `v<x.y.z>` tag, then drives the instance's `Makefile`
targets (`release-arches`, then per arch `build`, `sbom`,
`release-assets`, `publish`; once `release-check` in the devcontainer,
`finalize`, the GitHub Release with everything in `dist/`). Its `build`
job has `contents: write` only and hands the targets the `OCI_REGISTRY`
and `OCI_IMAGE_NAME` variables and the `OCI_REGISTRY_USERNAME` and
`OCI_REGISTRY_PASSWORD` secrets, the same registry credentials
`template-docker` uses for its image pushes. Its `GITHUB_TOKEN` can't
push packages.

The Dev Container CLI packages a collection (`devcontainer features
package src`, one `devcontainer-feature-<id>.tgz` per feature plus
`devcontainer-collection.json`) and publishes it (`devcontainer features
publish`), skipping every feature version already in the registry.

## Decision

We will release the collection through base's `release.yml`, implementing
its `Makefile` contract with `scripts/release-features.sh`:

- **Collection version.** The dispatched `release_type` and `bump` pick the
  tag, as in every craftainer repo. It versions the collection as a
  whole; each feature keeps its own version in its
  `devcontainer-feature.json`, which is still what consumers pin.
- **`release-arches`** prints `["amd64"]`: features are arch-independent
  shell, so they are packaged and published once.
- **`build`** packages every feature into `dist/` with the CLI version
  pinned in `scripts/develop.d/10-devcontainer-cli.sh`;
  **`release-assets`** checks `dist/` holds exactly those files. They are
  the GitHub Release's assets, on every channel.
- **`publish`** runs `devcontainer features publish` to
  `$OCI_REGISTRY/<OCI_IMAGE_NAME or owner/repo>/<id>` (here
  `ghcr.io/craftainer/devcontainer-features`) **only for a full release**:
  a `RELEASE_VERSION` with a pre-release suffix (alpha, beta, rc) skips it,
  so a pre-release builds and attaches the packages but pushes nothing.
  Without `OCI_REGISTRY` it skips with a warning, as the contract asks.
  It authenticates with the `OCI_REGISTRY_USERNAME` /
  `OCI_REGISTRY_PASSWORD` secrets through the CLI's
  `DEVCONTAINERS_OCI_AUTH` environment variable; on `ghcr.io` that is a
  classic personal access token with `write:packages`. `release.yml` runs
  `publish` in the `build` job, before `release-check`, and a pushed
  feature version can't be replaced, so `publish` runs `release-check`'s
  checks itself first and pushes nothing if they fail. It also refuses any
  leg but amd64, so a second arch can't race the first on the same tags.
- **`release-check`** (in the devcontainer) validates every
  `devcontainer-feature.json` (id matches its folder, name, SemVer version,
  option types and defaults), runs the feature-options and install-lib
  drift checks, and checks every package in `dist/` against `src/`'s ids
  and versions.
- **`sbom`, `finalize`, `publish-packages`, `verify-published`** are
  no-ops: there's no built binary to scan, nothing per arch to combine,
  and no package registry.
- **`features.yml`** no longer publishes. It validates and tests on pull
  requests and `main`, and after a successful, dispatched
  `.github/workflows/release.yml` run on `main` whose commit has a full
  (non-pre-release) GitHub Release, with `OCI_REGISTRY` set, its `docs` job opens
  the PR with the `src/<id>/README.md` files that `devcontainers/action`'s
  generate-docs regenerates. That job lives there, not in `finalize`,
  because `release.yml`'s token has no `pull-requests: write`.

## Consequences

- One way to cut a release across craftainer, with GitHub's generated
  notes and a Releases page. Merging to `main` publishes nothing.
- A change to a feature ships at the next full release, and only if that
  feature's `version` went up: the CLI skips versions already in the
  registry (`scripts/check-version-bump.sh` still enforces the bump on
  pull requests). The collection's bump is chosen by whoever dispatches
  the release; nothing derives it from the feature bumps.
- `publish` is re-runnable for the same reason. It packages `src/` again
  rather than pushing the `dist/` files, since the CLI can't publish a
  prebuilt package; both come from the same commit, and `release-check`
  checks the `dist/` copies.
- As the contract says for every image instance, `publish` runs in the
  `build` job, before `release-check`, so a full release whose
  `release-check` fails can already have pushed its feature versions.
- The registry push needs repository settings: the `OCI_REGISTRY`
  variable (`ghcr.io`) and the `OCI_REGISTRY_USERNAME` /
  `OCI_REGISTRY_PASSWORD` secrets. `OCI_IMAGE_NAME` is optional; it
  defaults to the repository. A full release without them publishes
  nothing and says so in a warning.
- Each new feature package on GHCR still starts private and is made
  public by hand once.
- `devcontainers/action` no longer tags `<id>_v<version>` in git; the
  collection's `v<x.y.z>` tags and the registry's own version tags remain.

## Amendment: publish to GHCR with `GITHUB_TOKEN` (2026-10-28)

The Decision's `publish` bullet authenticates only with the
`OCI_REGISTRY_USERNAME` / `OCI_REGISTRY_PASSWORD` secrets, on `ghcr.io` a
classic personal access token, because `release.yml`'s `build` job had
`contents: write` only. Base's `release.yml` now grants that job
`packages: write`, and GitHub's guidance ("Publishing and installing a
package with GitHub Actions") recommends the job's `GITHUB_TOKEN` over a
personal access token for pushing to the repository's own GHCR packages.

So `publish` now picks its credential this way, still passing it to the
CLI only through `DEVCONTAINERS_OCI_AUTH` and still rejecting a `|` or `,`
in any part of it:

- Either registry secret set: both secrets, as before (one alone fails).
  Explicit secrets always win.
- Neither set and `OCI_REGISTRY` is `ghcr.io`: `GITHUB_TOKEN` as
  `GITHUB_ACTOR`. Without `GITHUB_TOKEN` it fails, naming the
  `packages: write` the `build` job needs.
- Neither set and any other registry: fails, as before.

`OCI_REGISTRY` stays the opt-in: unset still skips with a warning, a
pre-release still pushes nothing, and only the amd64 leg publishes. On
GHCR, publishing now needs only the `OCI_REGISTRY` variable, once this
repo's synced `release.yml` carries `packages: write`; until template-sync
brings it in, the registry denies a full release's push when the secrets
are empty, and `publish` fails without pushing anything. A features-only
publish job triggered by `workflow_run` was considered instead and
rejected: it would split this repo's release path from every other
craftainer repo's.
