# shellcheck shell=bash
# The official flavor's Java check, sourced by install.sh (and by the
# tests, with fake javas). Every function here returns rather than exits,
# and none can abort a caller running under set -euo pipefail.

# kcadm_java: prints the java kcadm.sh would run, the way kcadm.sh picks
# it: $JAVA if set, else $JAVA_HOME/bin/java if JAVA_HOME is set, else java
# on PATH. A bare name is looked up on PATH. The result is resolved with
# readlink -f when it exists; otherwise the unresolved candidate is
# printed (a bare $JAVA not on PATH too), so a message can name it.
# Prints nothing when there is no candidate at all (no JAVA, no JAVA_HOME,
# no java on PATH).
kcadm_java() {
    local j
    if [ -n "${JAVA:-}" ]; then
        j="$JAVA"
    elif [ -n "${JAVA_HOME:-}" ]; then
        j="${JAVA_HOME}/bin/java"
    else
        j=java
    fi
    case "$j" in
        */*) ;;
        *)
            # A bare $JAVA not on PATH is printed as it is, so the message
            # names it; a missing default java prints nothing.
            if ! j="$(command -v -- "$j" 2>/dev/null)"; then
                [ -z "${JAVA:-}" ] || printf '%s\n' "$JAVA"
                return 0
            fi
            ;;
    esac
    if [ -e "$j" ]; then
        readlink -f -- "$j" 2>/dev/null || printf '%s\n' "$j"
    else
        printf '%s\n' "$j"
    fi
}

# java_major <java>: prints the major version <java> reports (e.g. 21), or
# "unknown" when it can't be run or doesn't report one. A failing or
# hanging java (60s) gives "unknown"; awk reads all its input, so there is
# no SIGPIPE.
java_major() {
    local out="" major=""
    out="$(timeout -k 5 60 "$1" -XshowSettings:properties -version 2>&1)" || true
    major="$(printf '%s\n' "$out" | awk -F'= ' '
        /^[[:space:]]*java\.specification\.version =/ && m == "" {
            v = $2; sub(/^1\./, "", v); split(v, p, "."); m = p[1]
        }
        END { print m }')" || true
    if [[ "$major" =~ ^[0-9]+$ ]]; then
        printf '%s\n' "$major"
    else
        printf 'unknown\n'
    fi
}

# check_kcadm_java <install_jre:true|false> <min_major>: checks the java
# kcadm.sh would run. With install_jre true, a missing java or one older
# than <min_major> (or of unknown version) fails (returns 1); with false,
# it only warns, and returns 0. Messages state what was found, by its
# resolved path.
check_kcadm_java() {
    local install_jre="$1" min="$2" bin major problem=""
    bin="$(kcadm_java)" || bin=""
    if [ -z "$bin" ]; then
        problem="no java found (JAVA and JAVA_HOME unset, no java on PATH)"
    elif [ ! -x "$bin" ] || [ -d "$bin" ]; then
        problem="no executable java at ${bin}"
    else
        major="$(java_major "$bin")" || major=unknown
        if [ "$major" = unknown ]; then
            problem="${bin} reports no Java version (it failed or printed none)"
        elif [ "$major" -lt "$min" ]; then
            problem="${bin} is Java ${major}"
        else
            echo "cli-keycloak: kcadm will run ${bin} (Java ${major})"
            return 0
        fi
    fi
    if [ "$install_jre" = true ]; then
        echo "cli-keycloak: ${problem}; kcadm needs Java ${min} or newer" >&2
        return 1
    fi
    echo "cli-keycloak: warning: ${problem}; kcadm needs Java ${min} or newer at run time (install_jre is false)" >&2
    return 0
}
