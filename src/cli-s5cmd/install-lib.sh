# shellcheck shell=bash
#
# install-lib.sh: shared helpers for this collection's install.sh scripts.
#
# The source of truth is common/install-lib.sh. A feature folder is
# packaged on its own, so each src/<id>/ carries a byte-identical copy that
# its install.sh sources; scripts/check-install-lib-drift.sh fails when a
# copy differs. Never edit a copy: change common/install-lib.sh and copy it
# into every src/*/ (each of those features then needs a version bump).
#
# Pin resolution is described in
# docs/adrs/0002-resolve-pins-from-option-env-or-pins-file-with-no-defaults.md;
# version-only pins for apt-installed CLIs (il_resolve_version,
# il_apt_add_repo, il_apt_install_pinned) in
# docs/adrs/0003-pin-apt-installed-clis-by-upstream-version-with-a-verified-repo-key.md.
#
# bash, not POSIX sh: every supported base image (Debian and Ubuntu) ships
# bash as an essential package. Sourcing this file sets no shell options;
# install.sh sets its own (set -euo pipefail). Every failure prints a
# message to stderr and exits 1, so install.sh fails at the right step.
#
# Every feature that calls il_resolve_pin or il_resolve_version must
# declare its "version", sha options (if any) and "pins_file" options with
# "default": "" (see il_resolve_pin); scripts/check-feature-options.sh
# enforces it.

# Prints "install-lib: <message>" to stderr and exits 1.
_il_die() {
    printf 'install-lib: %s\n' "$*" >&2
    exit 1
}

# il_require_root: exits 1 unless running as uid 0.
il_require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        _il_die "must run as root (uid 0), not uid $(id -u)"
    fi
}

# il_arch: prints amd64 or arm64 for this machine, exits 1 otherwise.
il_arch() {
    local machine
    machine="$(uname -m)"
    case "$machine" in
        x86_64 | amd64) echo amd64 ;;
        aarch64 | arm64) echo arm64 ;;
        *) _il_die "unsupported architecture '${machine}' (supported: amd64, arm64)" ;;
    esac
}

# il_apt_install <pkg>...: installs packages without recommends, then
# removes the apt lists so they don't stay in the image layer.
il_apt_install() {
    if [ "$#" -eq 0 ]; then
        _il_die "il_apt_install: no packages given"
    fi
    export DEBIAN_FRONTEND=noninteractive
    apt-get update || _il_die "apt-get update failed"
    apt-get install -y --no-install-recommends "$@" \
        || _il_die "apt-get install failed: $*"
    rm -rf /var/lib/apt/lists/*
}

# Prints the value of <key> from the pins file <file>, or nothing.
#
# The file is parsed, never sourced: only lines of the form KEY=value are
# read, after optional leading blanks and an optional "export" plus blanks.
# Blank lines and lines starting with # are skipped. Blanks after "=" are
# trimmed. A value that starts with a quote (' or ") runs to the next
# matching quote, and the rest of the line is ignored. An unquoted value
# ends before a trailing comment (blanks, then #), with trailing blanks
# dropped. Nothing is expanded. If a key appears more than once the last
# line wins, as it would when sourced.
_il_pins_get() {
    local file="$1" key="$2" line k v found=""
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%$'\r'}"
        line="${line#"${line%%[![:space:]]*}"}"
        case "$line" in
            '' | '#'*) continue ;;
        esac
        case "$line" in
            export[[:blank:]]*)
                line="${line#export}"
                line="${line#"${line%%[![:blank:]]*}"}"
                ;;
        esac
        k="${line%%=*}"
        [ "$k" = "$key" ] || continue
        [ "$k" != "$line" ] || continue # no "=" on this line
        v="${line#*=}"
        local trimmed="${v#"${v%%[![:blank:]]*}"}"
        # "KEY= # comment" sets nothing; "KEY=#x" keeps "#x", as sourcing does.
        [ "$trimmed" = "$v" ] || case "$trimmed" in '#'*) trimmed="" ;; esac
        v="$trimmed"
        # An unterminated quote is kept, so validation rejects the value.
        case "$v" in
            \"*\"*) v="${v#\"}" v="${v%%\"*}" ;;
            \'*\'*) v="${v#\'}" v="${v%%\'*}" ;;
            \"* | \'*) ;;
            *)
                v="${v%%[[:blank:]]#*}"
                v="${v%"${v##*[![:blank:]]}"}"
                ;;
        esac
        found="$v"
    done <"$file"
    printf '%s' "$found"
}

# il_resolve_pin <ID> <arch_specific:true|false>
#
# Resolves the version and sha256 to install and sets IL_VERSION and
# IL_SHA256 (lower-case hex) for the current arch. <ID> is the upper-cased
# feature id with "-" turned into "_", e.g. CLI_KEYCLOAK.
#
# Channels, in order; the first channel that is set is used:
#   1. options: $VERSION, and $SHA256_AMD64 / $SHA256_ARM64 (arch-specific)
#      or $SHA256 (arch-independent)
#   2. image environment: <ID>_VERSION, <ID>_SHA256_AMD64 / _ARM64 or
#      <ID>_SHA256
#   3. pins file: the same <ID>_* keys in $PINS_FILE (the pins_file
#      option), default /etc/devcontainer-features/pins.env
# A channel is set when it sets the version or any of its sha keys, for
# either arch: an arch-specific feature counts both _AMD64 and _ARM64. A
# set channel must supply the version and this arch's sha, or the install
# fails naming what is missing; it is never completed from, and never
# falls through to, a later channel. So a channel holding only the other
# arch's sha fails too. No channel at all is an error naming all three.
# There are no defaults. The version is validated (and a leading v
# rejected) before anything is logged as resolved.
#
# $VERSION is the generic name the "version" option arrives under, so
# install.sh must not set it before this call: read /etc/os-release in a
# subshell, e.g. codename="$(. /etc/os-release && echo "$VERSION_CODENAME")",
# never by sourcing it into install.sh's own shell. A VERSION inherited
# from the base image's ENV or exported by an earlier feature is shadowed
# only because every feature declares "version", its sha options and
# "pins_file" with "default": "": the Dev Container CLI writes each declared
# option, defaults included, to devcontainer-features.env and sources it
# with set -a before install.sh runs, so VERSION="" always replaces an
# inherited value.
il_resolve_pin() {
    local id="${1:-}" arch_specific="${2:-}" arch="" sha_key key
    local -a sha_keys
    _il_check_id il_resolve_pin "$id"
    case "$arch_specific" in
        true)
            arch="$(il_arch)" || exit 1
            sha_key="SHA256_${arch^^}"
            sha_keys=(SHA256_AMD64 SHA256_ARM64)
            ;;
        false)
            sha_key=SHA256
            sha_keys=(SHA256)
            ;;
        *) _il_die "il_resolve_pin: arch_specific must be true or false, not '${arch_specific}'" ;;
    esac

    local pins_file="${PINS_FILE:-/etc/devcontainer-features/pins.env}"
    local kind="" channel="" ver="" sha="" ver_name="" sha_name=""
    local -a set_names=()
    for kind in options env file; do
        if [ "$kind" = file ]; then
            [ -f "$pins_file" ] || break
            [ -r "$pins_file" ] || _il_die "pins file ${pins_file} is not readable"
        fi
        set_names=()
        for key in VERSION "${sha_keys[@]}"; do
            if [ -n "$(_il_pin_value "$kind" "$id" "$key" "$pins_file")" ]; then
                set_names+=("$(_il_pin_name "$kind" "$id" "$key")")
            fi
        done
        if [ "${#set_names[@]}" -gt 0 ]; then
            channel="$(_il_channel_desc "$kind" "$pins_file")"
            break
        fi
    done

    local env_ver="${id}_VERSION" env_sha="${id}_${sha_key}"
    if [ -z "$channel" ]; then
        _il_die "no pin for ${id}: set the version and ${sha_key,,}" \
            "feature options, or ${env_ver} and ${env_sha} in the image" \
            "environment, or in the pins file ${pins_file} ($(_il_pins_state "$pins_file" "neither key"))." \
            "There are no bundled defaults."
    fi
    ver="$(_il_pin_value "$kind" "$id" VERSION "$pins_file")"
    sha="$(_il_pin_value "$kind" "$id" "$sha_key" "$pins_file")"
    ver_name="$(_il_pin_name "$kind" "$id" VERSION)"
    sha_name="$(_il_pin_name "$kind" "$id" "$sha_key")"
    if [ -z "$ver" ] && [ -z "$sha" ]; then
        # Set only through the other arch's sha.
        _il_die "${channel} set ${set_names[*]} but not ${ver_name} or ${sha_name}" \
            "(this machine is ${arch}); set both in one place"
    fi
    if [ -z "$ver" ]; then
        _il_die "${channel} set ${sha_name} but not ${ver_name}; set both in one place"
    fi
    if [ -z "$sha" ]; then
        _il_die "${channel} set ${ver_name} but not ${sha_name}; set both in one place"
    fi
    case "$ver" in
        [!A-Za-z0-9]* | *[!A-Za-z0-9._+~-]*)
            _il_die "${channel}: ${ver_name} '${ver}' is not a valid version" ;;
        # Every release tag that has a v adds it itself; a pinned "v2.3.0"
        # would fetch tag vv2.3.0 and fail as an unexplained 404.
        [vV]*)
            _il_die "${channel}: ${ver_name} '${ver}' must not start with v (use ${ver#[vV]})" ;;
    esac
    sha="${sha,,}"
    if ! [[ "$sha" =~ ^[0-9a-f]{64}$ ]]; then
        _il_die "${channel}: ${sha_name} '${sha}' is not a sha256 (64 hex digits)"
    fi

    IL_VERSION="$ver"
    IL_SHA256="$sha"
    export IL_VERSION IL_SHA256
    echo "install-lib: ${id} ${IL_VERSION} (from ${channel})"
}

# il_resolve_version <ID>
#
# Resolves a version-only pin, for the apt-installed CLIs whose integrity
# comes from apt's signature check rather than a consumer sha (ADR 0003),
# and sets IL_VERSION. The channels and their order are il_resolve_pin's,
# for the version alone: the "version" option ($VERSION), then <ID>_VERSION
# in the image environment, then <ID>_VERSION in the pins file. The first
# channel that sets it wins; none is an error naming all three. The version
# must be an upstream version: digits and dots, e.g. 18.6 or 2.0.22, with no
# leading v and no distro revision. The same $VERSION caveat as
# il_resolve_pin applies.
il_resolve_version() {
    local id="${1:-}" kind="" channel="" ver=""
    _il_check_id il_resolve_version "$id"
    local pins_file="${PINS_FILE:-/etc/devcontainer-features/pins.env}"
    for kind in options env file; do
        if [ "$kind" = file ]; then
            [ -f "$pins_file" ] || break
            [ -r "$pins_file" ] || _il_die "pins file ${pins_file} is not readable"
        fi
        ver="$(_il_pin_value "$kind" "$id" VERSION "$pins_file")"
        if [ -n "$ver" ]; then
            channel="$(_il_channel_desc "$kind" "$pins_file")"
            break
        fi
    done
    if [ -z "$channel" ]; then
        _il_die "no version for ${id}: set the version feature option, or" \
            "${id}_VERSION in the image environment, or in the pins file" \
            "${pins_file} ($(_il_pins_state "$pins_file" "no ${id}_VERSION"))." \
            "There are no bundled defaults."
    fi
    if ! _il_is_upstream_version "$ver"; then
        _il_die "${channel}: $(_il_pin_name "$kind" "$id" VERSION) '${ver}' is not an" \
            "upstream version (digits and dots, e.g. 18.6; no leading v, no distro revision)"
    fi
    IL_VERSION="$ver"
    export IL_VERSION
    echo "install-lib: ${id} ${IL_VERSION} (from ${channel})"
}

# Fails unless <ID> (argument 2) looks like an upper-cased feature id;
# argument 1 names the caller.
_il_check_id() {
    case "$2" in
        '' | [!A-Z]* | *[!A-Z0-9_]*)
            _il_die "$1: invalid ID '$2' (expected e.g. CLI_KEYCLOAK)" ;;
    esac
}

# _il_pin_value <options|env|file> <ID> <KEY> <pins_file>: prints a pin
# channel's value for <KEY> (VERSION, SHA256, SHA256_AMD64, ...): the option
# variable <KEY> itself, <ID>_<KEY> from the environment, or <ID>_<KEY> from
# the pins file.
_il_pin_value() {
    local name
    case "$1" in
        options) name="$3" && printf '%s' "${!name:-}" ;;
        env) name="${2}_$3" && printf '%s' "${!name:-}" ;;
        file) _il_pins_get "$4" "${2}_$3" ;;
    esac
}

# _il_pin_name <options|env|file> <ID> <KEY>: prints how a channel names
# <KEY> in messages: the option id (version, sha256_amd64) or <ID>_<KEY>.
_il_pin_name() {
    case "$1" in
        options) printf '%s' "${3,,}" ;;
        *) printf '%s' "${2}_$3" ;;
    esac
}

# _il_channel_desc <options|env|file> <pins_file>: prints a channel's name.
_il_channel_desc() {
    case "$1" in
        options) printf 'the feature options' ;;
        env) printf 'the image environment' ;;
        file) printf 'the pins file %s' "$2" ;;
    esac
}

# _il_pins_state <pins_file> <what>: prints "not found", or "has <what>" for
# a pins file that exists but sets nothing for this feature.
_il_pins_state() {
    if [ -f "$1" ]; then
        printf 'has %s' "$2"
    else
        printf 'not found'
    fi
}

# Succeeds when $1 is an upstream version: digits and dots, starting and
# ending with a digit. [[ =~ ]] anchors to the whole string, so a value with
# a newline can't pass on its first line, as it would through grep.
_il_is_upstream_version() {
    [[ "$1" =~ ^[0-9]+(\.[0-9]+)*$ ]]
}

# Installs curl and the system CA bundle, each only if missing: debian:13
# and ubuntu:24.04 ship without either, and an image can have curl without
# ca-certificates, which would fail every https fetch with a TLS error.
_il_ensure_curl() {
    local -a pkgs=()
    command -v curl >/dev/null 2>&1 || pkgs+=(curl)
    [ -f /etc/ssl/certs/ca-certificates.crt ] || pkgs+=(ca-certificates)
    if [ "${#pkgs[@]}" -gt 0 ]; then
        il_apt_install "${pkgs[@]}"
    fi
}

# _il_curl <url> <dest>: downloads <url> to <dest>, with retries; on
# failure deletes <dest> and fails. Expects curl (see _il_ensure_curl).
#
# Two retry layers. curl's own --retry 3 covers timeouts (exit 28,
# including the connect timeout) and HTTP 408/429/5xx; with
# --retry-connrefused also ECONNREFUSED, but not other connect errors
# such as EHOSTUNREACH or ENETUNREACH. This loop retries what curl
# gives up on: DNS and connect failures (exit 6/7), resets and truncated
# transfers (18/52/55/56), as scripts/develop.sh's fetch does.
# Worst case: 4 curl calls of up to 4 attempts each, 16 attempts in
# all. --connect-timeout 10 bounds each attempt's connection phase (DNS,
# TCP and TLS) to 10s, so failing to connect costs at most about 200s
# (16 x 10s, plus curl's 7s of backoff per call and 12s of sleeps here).
# A transfer that stalls after connecting is not bounded: there is no
# --max-time, because artifact sizes vary, so it runs until the job's
# timeout. --retry-max-time 60 only stops a call starting new retries
# after 60s. A permanent HTTP error (-f, exit 22) or a TLS certificate
# failure still fails at once.
_il_curl() {
    local url="$1" dest="$2" call=1 calls=4 status
    while :; do
        status=0
        curl -fsSL --connect-timeout 10 --retry 3 --retry-max-time 60 \
            --retry-connrefused -o "$dest" "$url" || status=$?
        case "$status" in
            0) return 0 ;;
            6 | 7 | 18 | 52 | 55 | 56)
                if [ "$call" -lt "$calls" ]; then
                    echo "install-lib: curl exit ${status} (call ${call}/${calls}); retrying in $((call * 2))s: ${url}" >&2
                    sleep $((call * 2))
                    call=$((call + 1))
                    continue
                fi
                ;;
        esac
        rm -f "$dest"
        _il_die "download failed (curl exit ${status}, call ${call}/${calls}): ${url}"
    done
}

# il_fetch_verified <url> <sha256> <dest>: downloads <url> to <dest> and
# checks it against <sha256>. On a failed download or a mismatch, <dest> is
# deleted and the install fails. Installs curl and ca-certificates first if
# either is missing (debian:13 and ubuntu:24.04 ship without both).
il_fetch_verified() {
    local url="${1:-}" sha="${2:-}" dest="${3:-}"
    if [ -z "$url" ] || [ -z "$dest" ]; then
        _il_die "usage: il_fetch_verified <url> <sha256> <dest>"
    fi
    if ! [[ "$sha" =~ ^[0-9a-fA-F]{64}$ ]]; then
        _il_die "il_fetch_verified: '${sha}' is not a sha256 (64 hex digits)"
    fi
    _il_ensure_curl
    _il_curl "$url" "$dest"
    if ! echo "${sha}  ${dest}" | sha256sum -c -; then
        rm -f "$dest"
        _il_die "sha256 mismatch for ${url} (expected ${sha}); deleted ${dest}"
    fi
}

# il_apt_add_repo <name> <key_url> <fingerprint> <source_line>
#
# Adds a third-party apt repository whose signing key is pinned by
# fingerprint, a constant in the feature (ADR 0003). Fetches the key from
# <key_url> (https only), and fails unless it holds exactly one primary key
# whose fingerprint is <fingerprint> (40 hex digits; spaces are ignored and
# case doesn't matter). Then installs it, unarmored, as
# /etc/apt/keyrings/<name>.gpg and writes /etc/apt/sources.list.d/<name>.list
# with "deb [signed-by=/etc/apt/keyrings/<name>.gpg] <source_line>", e.g.
# <source_line> "https://apt.postgresql.org/pub/repos/apt trixie-pgdg main".
# Finally it runs apt-get update for that repository alone, with every
# warning an error, so a wrong suite or an unreachable or badly signed
# repository fails here rather than as a missing package later. On any
# failure the key and the list are removed and the install fails.
#
# Reading and unarmoring the key needs gpg, which bare debian:13 and
# ubuntu:24.04 lack; it is installed without recommends when missing, and
# runs with a throwaway GNUPGHOME, so no ~/.gnupg is left behind.
il_apt_add_repo() {
    if [ "$#" -ne 4 ]; then
        _il_die "usage: il_apt_add_repo <name> <key_url> <fingerprint> <source_line>"
    fi
    local name="$1" key_url="$2" fpr="$3" source_line="$4"
    if ! [[ "$name" =~ ^[a-z0-9][a-z0-9._-]*$ ]]; then
        _il_die "il_apt_add_repo: invalid name '${name}' (lower-case letters, digits, . _ -)"
    fi
    case "$key_url" in
        https://?*) ;;
        *) _il_die "il_apt_add_repo: key URL '${key_url}' must be https://" ;;
    esac
    fpr="${fpr// /}"
    fpr="${fpr^^}"
    if ! [[ "$fpr" =~ ^[0-9A-F]{40}$ ]]; then
        _il_die "il_apt_add_repo: '$3' is not an OpenPGP v4 fingerprint (40 hex digits)"
    fi
    if [ -z "$source_line" ] || [[ "$source_line" == *[$'\n\r']* ]]; then
        _il_die "il_apt_add_repo: the source line must be one non-empty line"
    fi

    local keyring="/etc/apt/keyrings/${name}.gpg"
    local list="/etc/apt/sources.list.d/${name}.list"
    local tmp status=0
    _il_ensure_curl
    if ! command -v gpg >/dev/null 2>&1; then
        il_apt_install gpg
    fi
    tmp="$(mktemp -d)" || _il_die "il_apt_add_repo: cannot create a temporary directory"
    # A subshell, so a failure inside still reaches the cleanup below
    # (install.sh may own the EXIT trap).
    _il_apt_key_prepare "$key_url" "$fpr" "$tmp" || status=$?
    if [ "$status" -ne 0 ]; then
        rm -rf "$tmp"
        exit 1
    fi
    if ! install -d -m 0755 /etc/apt/keyrings \
        || ! install -m 0644 "${tmp}/keyring.gpg" "$keyring" \
        || ! printf 'deb [signed-by=%s] %s\n' "$keyring" "$source_line" >"$list"; then
        rm -rf "$tmp"
        rm -f "$keyring" "$list"
        _il_die "il_apt_add_repo: cannot write ${keyring} or ${list}"
    fi
    rm -rf "$tmp"
    echo "install-lib: added apt repository ${name} (key ${fpr})"
    export DEBIAN_FRONTEND=noninteractive
    if ! apt-get update --error-on=any \
        -o Dir::Etc::SourceList="$list" -o Dir::Etc::SourceParts=- \
        -o APT::Get::List-Cleanup=0; then
        rm -f "$keyring" "$list"
        _il_die "apt-get update failed for the ${name} repository (${source_line}); removed ${keyring} and ${list}"
    fi
}

# _il_apt_key_prepare <key_url> <fingerprint> <tmp>: fetches the key into
# <tmp>, unarmors it to <tmp>/keyring.gpg and checks that the result holds
# exactly the one primary key <fingerprint>. Runs in a subshell, so its
# GNUPGHOME and its exit on failure stay inside it.
_il_apt_key_prepare() (
    key_url="$1" fpr="$2" tmp="$3"
    export GNUPGHOME="${tmp}/gnupg"
    mkdir -m 0700 "$GNUPGHOME" || _il_die "il_apt_add_repo: cannot create ${GNUPGHOME}"
    _il_curl "$key_url" "${tmp}/key"
    [ -s "${tmp}/key" ] || _il_die "il_apt_add_repo: ${key_url} is empty"
    # The key is served armored (PGDG) or binary (mosquitto); apt's
    # signed-by .gpg file takes binary.
    if grep -q -- '-----BEGIN PGP PUBLIC KEY BLOCK-----' "${tmp}/key"; then
        gpg --batch --quiet --dearmor -o "${tmp}/keyring.gpg" "${tmp}/key" \
            || _il_die "il_apt_add_repo: cannot unarmor the key from ${key_url}"
    else
        cp "${tmp}/key" "${tmp}/keyring.gpg"
    fi
    # The fingerprint is checked on the exact bytes apt will trust. Every
    # primary key counts: a second one would be trusted for the repository
    # too.
    gpg --batch --with-colons --show-keys "${tmp}/keyring.gpg" >"${tmp}/keys" 2>"${tmp}/gpg.err" \
        || _il_die "il_apt_add_repo: ${key_url} is not an OpenPGP public key: $(head -c 500 "${tmp}/gpg.err")"
    got="$(awk -F: '$1 == "pub" { want = 1; next } want && $1 == "fpr" { print $10; want = 0 }' "${tmp}/keys")"
    if [ "$got" != "$fpr" ]; then
        _il_die "il_apt_add_repo: the key from ${key_url} has fingerprint" \
            "'$(printf '%s' "$got" | tr '\n' ' ')', expected ${fpr}; not adding the repository"
    fi
)

# il_apt_install_pinned <pkg> <version>: installs <pkg> at the upstream
# <version> (e.g. 18.6, 2.0.22; digits and dots), whatever the distro's
# revision (ADR 0003). Runs apt-get update, then picks from
# `apt-cache madison <pkg>` the candidate whose version is exactly
# <version>-<revision>, optionally with an epoch ("N:"). Exactly one
# candidate is installed with --no-install-recommends; none, or several,
# fail listing the versions available. apt checks the repository's
# signature; there is no sha. Removes the apt lists afterwards, like
# il_apt_install.
#
# apt pins only the package named on the command line: a dependency keeps
# its newest candidate, so mosquitto-clients 2.0.22, which Depends on
# libmosquitto1 (= 2.0.22-...), can't install once 2.1.x is in the repo.
# So every unconditional exact-version dependency (an entry "name (= v)" in
# Depends or Pre-Depends, not part of an "a | b" alternative) is pinned to
# that version in the same apt-get install, transitively. An arch qualifier
# :any or :native is dropped (the native package is pinned), any other is
# kept. Alternatives and ">=" or "<<" entries are left to apt. The pinned
# dependencies are then marked automatically installed, unless they were
# already installed manually, so only <pkg> stays manual.
il_apt_install_pinned() {
    if [ "$#" -ne 2 ]; then
        _il_die "usage: il_apt_install_pinned <pkg> <version>"
    fi
    local pkg="$1" version="$2" available candidate
    local -a matches=()
    if ! [[ "$pkg" =~ ^[a-z0-9][a-z0-9+.-]+$ ]]; then
        _il_die "il_apt_install_pinned: invalid package name '${pkg}'"
    fi
    if ! _il_is_upstream_version "$version"; then
        _il_die "il_apt_install_pinned: '${version}' is not an upstream version" \
            "(digits and dots, e.g. 18.6; no leading v, no distro revision)"
    fi
    export DEBIAN_FRONTEND=noninteractive
    apt-get update || _il_die "apt-get update failed"
    # madison prints "pkg | version | source Packages" per version and
    # source; Sources lines (deb-src) are skipped.
    available="$(apt-cache madison "$pkg" \
        | awk -F'|' '$3 ~ /Packages[[:space:]]*$/ { gsub(/[[:space:]]/, "", $2); print $2 }' \
        | sort -uV)" || true
    if [ -z "$available" ]; then
        _il_die "il_apt_install_pinned: no package ${pkg} in the configured apt sources"
    fi
    while IFS= read -r candidate; do
        if [[ "$candidate" =~ ^([0-9]+:)?([^:]+)-[A-Za-z0-9.+~]+$ ]] \
            && [ "${BASH_REMATCH[2]}" = "$version" ]; then
            matches+=("$candidate")
        fi
    done <<<"$available"
    case "${#matches[@]}" in
        0)
            _il_die "il_apt_install_pinned: no ${pkg} ${version}-<revision> in the configured" \
                "apt sources; available: $(printf '%s' "$available" | tr '\n' ' ')" ;;
        1) ;;
        *)
            _il_die "il_apt_install_pinned: several ${pkg} candidates for ${version}:" \
                "${matches[*]}; the pin can't choose between them" ;;
    esac
    local -a deps=() auto=()
    local dep manual
    mapfile -t deps < <(_il_apt_exact_deps "$pkg" "${matches[0]}")
    if [ "${#deps[@]}" -gt 0 ] && [ -z "${deps[-1]}" ]; then
        exit 1 # _il_apt_exact_deps failed; it printed why
    fi
    manual="$(apt-mark showmanual 2>/dev/null || true)"
    for dep in "${deps[@]}"; do
        if ! grep -Fqx -- "${dep%%=*}" <<<"$manual"; then
            auto+=("${dep%%=*}")
        fi
    done
    echo "install-lib: installing ${pkg}=${matches[0]} ${deps[*]}"
    apt-get install -y --no-install-recommends "${pkg}=${matches[0]}" "${deps[@]}" \
        || _il_die "apt-get install failed: ${pkg}=${matches[0]} ${deps[*]}"
    if [ "${#auto[@]}" -gt 0 ]; then
        apt-mark auto "${auto[@]}" >/dev/null \
            || _il_die "apt-mark auto failed: ${auto[*]}"
    fi
    rm -rf /var/lib/apt/lists/*
}

# _il_apt_exact_deps <pkg> <version>: prints "name=version" for every
# unconditional exact-version dependency of <pkg> <version>, transitively
# (see il_apt_install_pinned). On a failure it prints the reason to stderr
# and an empty last line, which the caller checks (it runs in a process
# substitution, so it can't exit the install itself).
_il_apt_exact_deps() {
    local -a queue=("$1=$2")
    local -A pinned=([$1]="$2")
    local item entry name ver
    # name, optional :arch, then "(= version)".
    local re='^([a-z0-9][a-z0-9+.-]+)(:[a-z0-9-]+)?[[:space:]]*\(=[[:space:]]*([^[:space:])]+)\)$'
    while [ "${#queue[@]}" -gt 0 ]; do
        item="${queue[0]}"
        queue=("${queue[@]:1}")
        # The first record only: several sources can carry the same version.
        while IFS= read -r entry; do
            entry="${entry#"${entry%%[![:space:]]*}"}"
            entry="${entry%"${entry##*[![:space:]]}"}"
            [[ "$entry" == *'|'* ]] && continue
            [[ "$entry" =~ $re ]] || continue
            name="${BASH_REMATCH[1]}"
            case "${BASH_REMATCH[2]}" in
                '' | :any | :native) ;;
                *) name="${name}${BASH_REMATCH[2]}" ;;
            esac
            ver="${BASH_REMATCH[3]}"
            if [ -n "${pinned[$name]:-}" ]; then
                if [ "${pinned[$name]}" != "$ver" ]; then
                    printf 'install-lib: il_apt_install_pinned: %s is required at both %s and %s\n' \
                        "$name" "${pinned[$name]}" "$ver" >&2
                    echo
                    return 1
                fi
                continue
            fi
            pinned[$name]="$ver"
            printf '%s=%s\n' "$name" "$ver"
            queue+=("${name}=${ver}")
        done < <(apt-cache show "$item" 2>/dev/null \
            | awk '/^$/ { exit } /^(Pre-)?Depends:/ { sub(/^[^:]*:/, ""); print }' \
            | tr ',' '\n')
    done
}

# il_install_bin <src> <name>: installs <src> as /usr/local/bin/<name>,
# mode 0755.
il_install_bin() {
    local src="${1:-}" name="${2:-}"
    case "$name" in
        '' | */* | . | ..) _il_die "il_install_bin: invalid name '${name}'" ;;
    esac
    [ -f "$src" ] || _il_die "il_install_bin: no such file '${src}'"
    install -m 0755 "$src" "/usr/local/bin/${name}" || _il_die "il_install_bin: cannot install ${name}"
}

# il_user_state_dir <path-relative-to-home>...: creates each directory
# under $_REMOTE_USER_HOME, owned by $_REMOTE_USER, mode 0700. Parent
# directories it has to create (e.g. ~/.config) are owned by the user too,
# mode 0755; parents that already exist are left alone, except that a
# symlink at any component under the home is refused. A named volume
# mounted on the directory later starts out with this ownership.
il_user_state_dir() {
    local user="${_REMOTE_USER:-}" home="${_REMOTE_USER_HOME:-}" group rel dir part
    local -a parts
    [ -n "$user" ] || _il_die "il_user_state_dir: _REMOTE_USER is not set"
    [ -n "$home" ] || _il_die "il_user_state_dir: _REMOTE_USER_HOME is not set"
    [ -d "$home" ] || _il_die "il_user_state_dir: home ${home} does not exist"
    group="$(id -gn "$user")" || _il_die "il_user_state_dir: unknown user '${user}'"
    [ "$#" -gt 0 ] || _il_die "il_user_state_dir: no directories given"
    for rel in "$@"; do
        case "$rel" in
            '' | /*) _il_die "il_user_state_dir: '${rel}' must be a path relative to the home directory" ;;
        esac
        case "/${rel}/" in
            */../* | */./*) _il_die "il_user_state_dir: '${rel}' must not contain . or .. components" ;;
        esac
        IFS=/ read -ra parts <<<"$rel"
        dir="$home"
        for part in "${parts[@]}"; do
            [ -n "$part" ] || continue
            dir="${dir}/${part}"
            # chown and chmod follow symlinks, and mkdir creates under a
            # symlinked parent, so any symlinked component would hand (part
            # of) its target to the user; refuse it instead.
            if [ -L "$dir" ]; then
                _il_die "il_user_state_dir: ${dir} is a symlink; refusing to change its target"
            fi
            if [ ! -d "$dir" ]; then
                mkdir -m 0755 "$dir" || _il_die "il_user_state_dir: cannot create ${dir}"
                chown "${user}:${group}" "$dir" || _il_die "il_user_state_dir: cannot chown ${dir}"
            fi
        done
        chown "${user}:${group}" "$dir" || _il_die "il_user_state_dir: cannot chown ${dir}"
        chmod 0700 "$dir" || _il_die "il_user_state_dir: cannot chmod ${dir}"
    done
}
