# This collection's implementation of template-base's release contract
# (docs/TEMPLATE.md, "Release: a Makefile contract"), driven by the synced
# release.yml; see docs/adrs/0004-collection-github-releases.md. The work is
# in scripts/release-features.sh. Instance-owned: template sync never
# touches this file.
#
# A release packages every feature under src/ into dist/ (attached to the
# GitHub Release); only a full release (no -alpha/-beta/-rc suffix) also
# pushes the features to the OCI registry. Each feature keeps its own
# version from its devcontainer-feature.json; RELEASE_VERSION is the
# collection's.

.PHONY: release-arches build sbom release-assets publish publish-packages verify-published release-check finalize

# Prints (only) a JSON array of the arches to build on, once, first. Features
# are arch-independent shell, packaged and published once: one leg only, so
# the dist/ file names need no arch.
release-arches:
	@echo '["amd64"]'

# Host runner: packages every src/<id>/ into dist/ as
# devcontainer-feature-<id>.tgz plus devcontainer-collection.json, with the
# pinned Dev Container CLI.
build:
	scripts/release-features.sh build

# Features are shell scripts copied into the consumer's image; there is no
# built binary or image to scan.
sbom:
	@echo "devcontainer-features ships shell scripts, not a built artifact -- nothing to scan."

# Host runner: build already wrote dist/; check it holds exactly one package
# per feature plus the collection file, and list it.
release-assets:
	scripts/release-features.sh assets

# Host runner, per arch (one leg): `devcontainer features publish` to
# $(OCI_REGISTRY)/$(OCI_IMAGE_NAME or GITHUB_REPOSITORY)/<id>, only for a full
# release; a pre-release, or no OCI_REGISTRY, skips cleanly. Runs
# release-check's checks first (this runs before release-check, and a pushed
# version can't be replaced) and only on the amd64 leg. Re-runnable: the
# CLI skips feature versions already in the registry.
publish:
	scripts/release-features.sh publish

# Once, after every arch leg, and only when the instance sets PYPI_PUBLISH,
# NPM_PUBLISH or CARGO_PUBLISH: PyPI / npm / crates.io. dist/ holds every
# arch leg's files.
# This default must not silently skip a configured publish: an instance that
# sets a *_PUBLISH variable but still uploads from `publish` would otherwise
# release without its package.
publish-packages:
	@set -e; \
	for v in PYPI_PUBLISH NPM_PUBLISH CARGO_PUBLISH; do \
	  if [ -n "$$(printenv $$v)" ]; then \
	    echo "error: this instance sets $$v but its Makefile doesn't implement publish-packages; move the package upload from publish into publish-packages (see docs/TEMPLATE.md)" >&2; \
	    exit 1; \
	  fi; \
	done; \
	echo "devcontainer-features ships no package -- nothing to publish."

# Once, after publish-packages succeeded, and only when the instance sets
# PYPI_PUBLISH, NPM_PUBLISH or CARGO_PUBLISH. This repo sets none of them.
verify-published:
	@echo "devcontainer-features ships no package -- nothing to verify."

# Runs once after every arch leg, inside the devcontainer: validates every
# devcontainer-feature.json, runs the feature-options and install-lib drift
# checks, and checks dist/ against src/ (ids and versions). Gates the GitHub
# Release (not the registry publish, which already ran in build's job).
release-check:
	scripts/release-features.sh check

# Runs once after release-check, on the host runner. Nothing is per arch, so
# there is nothing to combine. The regenerated src/<id>/README.md PR comes
# from features.yml's docs job after a full release, not from here: this job's
# token can't open a PR.
finalize:
	@echo "devcontainer-features has no cross-arch work -- nothing to finalize."
