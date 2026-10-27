#!/usr/bin/env bash
# The Dev Container CLI, so `devcontainer features test` runs inside this
# repo's own devcontainer (docker-in-docker comes from template-base). Node
# and npm are already on PATH from ../develop.sh.
#
# Installed from the npm registry at an exact version. npm checks the
# tarball against the registry's sha512 `integrity` itself; the package has
# no dependencies and no install scripts (--ignore-scripts keeps it that
# way if a later release adds one). It goes to its own /usr/local prefix,
# not Node's install directory, so a Node bump in ../develop.sh doesn't
# move it.
set -euo pipefail

# renovate: datasource=npm depName=@devcontainers/cli
DEVCONTAINER_CLI_VERSION=0.89.0

npm_cache="$(mktemp -d)"
trap 'rm -rf "$npm_cache"' EXIT

# npm does its own downloads, so (like ../develop.sh's installers) only the
# whole install is retried, a bounded number of times with doubling delays,
# so CI's shared-IP registry errors don't fail the image build. A copy of
# ../develop.sh's retry() (this hook runs on its own, so it can't source
# that one); keep the two in step when base changes it.
retry() {
    local attempt=1 max=4 delay=5
    until "$@"; do
        if [ "$attempt" -ge "$max" ]; then
            echo "giving up after $max attempts: $*" >&2
            return 1
        fi
        echo "attempt $attempt/$max failed; retrying in ${delay}s: $*" >&2
        sleep "$delay"
        attempt=$((attempt + 1))
        delay=$((delay * 2))
    done
}

retry npm install --global --prefix /usr/local --cache "$npm_cache" \
    --ignore-scripts --no-audit --no-fund --no-update-notifier \
    "@devcontainers/cli@${DEVCONTAINER_CLI_VERSION}"

# Verify what landed on PATH is the pinned version, not some other copy.
installed="$(/usr/local/bin/devcontainer --version)"
if [ "$installed" != "$DEVCONTAINER_CLI_VERSION" ]; then
    echo "devcontainer --version is '${installed}', expected ${DEVCONTAINER_CLI_VERSION}" >&2
    exit 1
fi
