#!/usr/bin/env bash
# Fails when any src/<id>/install-lib.sh differs from common/install-lib.sh.
#
# A feature folder is packaged on its own, so each feature carries a
# verbatim copy of the shared library (see common/install-lib.sh's header).
# Passes when there is no src/ or no copy yet. Run from the repo root.
set -euo pipefail

lib=common/install-lib.sh
if [ ! -f "$lib" ]; then
    echo "check-install-lib-drift: ${lib} is missing" >&2
    exit 1
fi

status=0
shopt -s nullglob
for copy in src/*/install-lib.sh; do
    if ! cmp -s "$lib" "$copy"; then
        echo "check-install-lib-drift: ${copy} differs from ${lib}; copy it again with: cp ${lib} ${copy}" >&2
        status=1
    fi
done
exit "$status"
