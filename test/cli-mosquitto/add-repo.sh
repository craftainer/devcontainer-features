#!/usr/bin/env bash
# add-repo.sh <install-lib.sh> <name> <key_url> <fingerprint> <source_line>:
# calls il_apt_add_repo from the given library copy with install.sh's shell
# options. rejects_bad_pins.sh runs it as root to check a wrong fingerprint.
set -euo pipefail
# shellcheck source=/dev/null
. "$1"
shift
il_apt_add_repo "$@"
