#!/usr/bin/env bash
# Installs Anthropic's native Claude Code binary as /usr/local/bin/claude,
# downloaded from Anthropic's release bucket for this arch and checked
# against the consumer's sha256. The version and sha come from the feature
# options, the image environment (CLI_CLAUDE_CODE_*) or the pins file; see
# NOTES.md and
# docs/adrs/0002-resolve-pins-from-option-env-or-pins-file-with-no-defaults.md.
#
# The URL is the one the official installer (https://claude.ai/install.sh)
# downloads: https://downloads.claude.ai/claude-code-releases/<version>/<platform>/claude,
# where <platform> is linux-x64 or linux-arm64 (glibc; the bucket's separate
# linux-*-musl builds are for Alpine, which this collection doesn't support).
# The official installer also reads <version>/manifest.json for the sha; this
# feature doesn't, because the consumer's sha is the check.
set -euo pipefail
# shellcheck source=install-lib.sh
. "$(dirname "$0")/install-lib.sh"

il_require_root
il_resolve_pin CLI_CLAUDE_CODE true

arch="$(il_arch)"
case "$arch" in
    amd64) platform=linux-x64 ;;
    arm64) platform=linux-arm64 ;;
esac

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

url="https://downloads.claude.ai/claude-code-releases/${IL_VERSION}/${platform}/claude"
il_fetch_verified "$url" "$IL_SHA256" "${tmp}/claude"
il_install_bin "${tmp}/claude" claude

# Claude Code keeps its settings, credentials and session history in
# ~/.claude. Consumers who keep that state across rebuilds mount a named
# volume there (NOTES.md). Docker seeds an empty named volume with the
# ownership and mode of the image directory it is mounted on, and creates
# that directory root-owned when the image doesn't have it. So the
# directory is created here, owned by the remote user with mode 0700:
# without it, a fresh volume comes up owned by root and Claude Code can't
# write to it.
il_user_state_dir .claude

echo "cli-claude-code: installed $(/usr/local/bin/claude --version)"
