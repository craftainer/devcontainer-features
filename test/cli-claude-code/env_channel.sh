#!/usr/bin/env bash
# The image-environment channel: env_channel/Dockerfile sets
# CLI_CLAUDE_CODE_* with ENV, and the scenario sets no options.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=claude-code-checks.sh
source "$(dirname "$0")/claude-code-checks.sh"

check "CLI_CLAUDE_CODE_VERSION is set in the image" test -n "${CLI_CLAUDE_CODE_VERSION:-}"
expect_installed "${CLI_CLAUDE_CODE_VERSION:-}"

reportResults
