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
# docs/adrs/0002-resolve-pins-from-option-env-or-pins-file-with-no-defaults.md.
#
# bash, not POSIX sh: every supported base image (Debian and Ubuntu) ships
# bash as an essential package. Sourcing this file sets no shell options;
# install.sh sets its own (set -euo pipefail). Every failure prints a
# message to stderr and exits 1, so install.sh fails at the right step.

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

# TODO(G5): il_apt_install_pinned <pkg> <version> goes here, implementing
# the verification method gate G5 picks for apt-installed CLIs
# (cli-postgres-client, cli-valkey, cli-mosquitto). Deliberately not
# defined yet: a feature that needs it must wait for that DF1 follow-up.

# Prints the value of <key> from the pins file <file>, or nothing.
#
# The file is parsed, never sourced: only lines of the form KEY=value are
# read, after optional leading blanks and an optional "export" plus blanks.
# Blank lines and lines starting with # are skipped. A trailing comment
# (blanks, then #) and trailing blanks are dropped, then one pair of
# matching surrounding quotes ('...' or "...") is stripped; nothing is
# expanded, and a value can't contain " #". If a key appears more than
# once the last line wins, as it would when sourced.
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
        v="${v%%[[:blank:]]#*}"
        v="${v%"${v##*[![:blank:]]}"}"
        case "$v" in
            \"*\") v="${v#\"}" v="${v%\"}" ;;
            \'*\') v="${v#\'}" v="${v%\'}" ;;
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
# Channels, in order; the first channel that sets either value is used:
#   1. options: $VERSION, and $SHA256_AMD64 / $SHA256_ARM64 (arch-specific)
#      or $SHA256 (arch-independent)
#   2. image environment: <ID>_VERSION, <ID>_SHA256_AMD64 / _ARM64 or
#      <ID>_SHA256
#   3. pins file: the same <ID>_* keys in $PINS_FILE (the pins_file
#      option), default /etc/devcontainer-features/pins.env
# Version and sha always come from the same channel. A channel that sets
# one without the other is an error, never completed from a later channel.
# No channel at all is an error naming all three. There are no defaults.
#
# $VERSION is the generic name the "version" option arrives under, so
# install.sh must not set it before this call: read /etc/os-release in a
# subshell, e.g. codename="$(. /etc/os-release && echo "$VERSION_CODENAME")",
# never by sourcing it into install.sh's own shell.
il_resolve_pin() {
    local id="${1:-}" arch_specific="${2:-}" arch sha_opt
    case "$id" in
        '' | [!A-Z]* | *[!A-Z0-9_]*)
            _il_die "il_resolve_pin: invalid ID '${id}' (expected e.g. CLI_KEYCLOAK)" ;;
    esac
    case "$arch_specific" in
        true)
            arch="$(il_arch)" || exit 1
            sha_opt="SHA256_$(printf '%s' "$arch" | tr '[:lower:]' '[:upper:]')"
            ;;
        false) sha_opt=SHA256 ;;
        *) _il_die "il_resolve_pin: arch_specific must be true or false, not '${arch_specific}'" ;;
    esac

    local pins_file="${PINS_FILE:-/etc/devcontainer-features/pins.env}"
    local env_ver="${id}_VERSION" env_sha="${id}_${sha_opt}"
    local opt_ver_name=version opt_sha_name
    opt_sha_name="$(printf '%s' "$sha_opt" | tr '[:upper:]' '[:lower:]')"

    local channel="" ver="" sha="" ver_name="" sha_name=""
    if [ -n "${VERSION:-}" ] || [ -n "${!sha_opt:-}" ]; then
        channel="the feature options"
        ver="${VERSION:-}" sha="${!sha_opt:-}"
        ver_name="$opt_ver_name" sha_name="$opt_sha_name"
    elif [ -n "${!env_ver:-}" ] || [ -n "${!env_sha:-}" ]; then
        channel="the image environment"
        ver="${!env_ver:-}" sha="${!env_sha:-}"
        ver_name="$env_ver" sha_name="$env_sha"
    elif [ -f "$pins_file" ]; then
        [ -r "$pins_file" ] || _il_die "pins file ${pins_file} is not readable"
        ver="$(_il_pins_get "$pins_file" "$env_ver")"
        sha="$(_il_pins_get "$pins_file" "$env_sha")"
        if [ -n "$ver" ] || [ -n "$sha" ]; then
            channel="the pins file ${pins_file}"
            ver_name="$env_ver" sha_name="$env_sha"
        fi
    fi

    if [ -z "$channel" ]; then
        local pins_state="not found"
        [ ! -f "$pins_file" ] || pins_state="has neither key"
        _il_die "no pin for ${id}: set the ${opt_ver_name} and ${opt_sha_name}" \
            "feature options, or ${env_ver} and ${env_sha} in the image" \
            "environment, or in the pins file ${pins_file} (${pins_state})." \
            "There are no bundled defaults."
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
    esac
    sha="$(printf '%s' "$sha" | tr '[:upper:]' '[:lower:]')"
    if ! printf '%s' "$sha" | grep -Eq '^[0-9a-f]{64}$'; then
        _il_die "${channel}: ${sha_name} '${sha}' is not a sha256 (64 hex digits)"
    fi

    IL_VERSION="$ver"
    IL_SHA256="$sha"
    export IL_VERSION IL_SHA256
    echo "install-lib: ${id} ${IL_VERSION} (from ${channel})"
}

# il_fetch_verified <url> <sha256> <dest>: downloads <url> to <dest> and
# checks it against <sha256>. On a failed download or a mismatch, <dest> is
# deleted and the install fails. Installs curl and ca-certificates first if
# curl is missing (debian:13 and ubuntu:24.04 ship without it).
il_fetch_verified() {
    local url="${1:-}" sha="${2:-}" dest="${3:-}"
    if [ -z "$url" ] || [ -z "$dest" ]; then
        _il_die "usage: il_fetch_verified <url> <sha256> <dest>"
    fi
    if ! printf '%s' "$sha" | grep -Eq '^[0-9a-fA-F]{64}$'; then
        _il_die "il_fetch_verified: '${sha}' is not a sha256 (64 hex digits)"
    fi
    if ! command -v curl >/dev/null 2>&1; then
        il_apt_install curl ca-certificates
    fi
    # curl's --retry (+ --retry-connrefused) covers timeouts, refused
    # connections and HTTP 408/429/5xx. DNS and connect failures (exit 6/7),
    # resets and truncated transfers (18/52/55/56) are retried here, at most
    # 4 tries, as in scripts/develop.sh's fetch; a permanent HTTP error (-f,
    # exit 22) or a TLS failure still fails at once.
    local attempt=1 status
    while :; do
        status=0
        curl -fsSL --retry 3 --retry-max-time 60 --retry-connrefused \
            -o "$dest" "$url" || status=$?
        case "$status" in
            0) break ;;
            6 | 7 | 18 | 52 | 55 | 56)
                if [ "$attempt" -lt 4 ]; then
                    echo "install-lib: curl exit ${status}; retrying (${attempt}/3): ${url}" >&2
                    sleep $((attempt * 2))
                    attempt=$((attempt + 1))
                    continue
                fi
                ;;
        esac
        rm -f "$dest"
        _il_die "download failed (curl exit ${status}): ${url}"
    done
    if ! echo "${sha}  ${dest}" | sha256sum -c -; then
        rm -f "$dest"
        _il_die "sha256 mismatch for ${url} (expected ${sha}); deleted ${dest}"
    fi
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
# mode 0755; parents that already exist are left alone. A named volume
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
            if [ ! -d "$dir" ]; then
                mkdir -m 0755 "$dir" || _il_die "il_user_state_dir: cannot create ${dir}"
                chown "${user}:${group}" "$dir" || _il_die "il_user_state_dir: cannot chown ${dir}"
            fi
        done
        # chown and chmod follow symlinks, so a symlinked state dir would
        # hand its target to the user; refuse it instead.
        if [ -L "$dir" ]; then
            _il_die "il_user_state_dir: ${dir} is a symlink; refusing to change its target"
        fi
        chown "${user}:${group}" "$dir" || _il_die "il_user_state_dir: cannot chown ${dir}"
        chmod 0700 "$dir" || _il_die "il_user_state_dir: cannot chmod ${dir}"
    done
}
