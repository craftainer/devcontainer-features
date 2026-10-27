#!/usr/bin/env bash
# Negative cases. The scenario installs the rest flavor first (no download);
# this script then runs the feature's install.sh again with bad inputs and
# checks that each run fails with the expected message, leaves no file
# behind in its TMPDIR, doesn't touch the installed kcadm and installs
# nothing of the official flavor. An expected failure can't be a scenario
# of its own, because a failed install fails the whole run
# (docs/adrs/0002-resolve-pins-from-option-env-or-pins-file-with-no-defaults.md).
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=keycloak-checks.sh
source "$(dirname "$0")/keycloak-checks.sh"

expect_rest

install_sh="${feature_dir}/install.sh"
installed_sha="$(sha256sum /usr/local/bin/kcadm)"
# A real release, so the wrong-sha case reaches the download.
version="$(scenario_version official_option)"
zeros="$(printf '%064d' 0)"
version_pins="$(mktemp)"
printf 'CLI_KEYCLOAK_VERSION=%s\n' "$version" >"$version_pins"
flavor_pins="$(mktemp)"
printf 'CLI_KEYCLOAK_FLAVOR=bogus\n' >"$flavor_pins"
chmod 0644 "$version_pins" "$flavor_pins"

as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

# expect_rejected <ERE> [VAR=value...]: runs install.sh as root in a clean
# environment with only the given variables, and succeeds when it fails,
# its output matches <ERE>, its TMPDIR is left empty, the installed kcadm
# is unchanged and nothing of the official flavor was installed.
expect_rejected() {
    local scratch result=0
    scratch="$(mktemp -d)" || return 1
    _expect_rejected_in "$scratch" "$@" || result=$?
    as_root rm -rf "$scratch"
    return "$result"
}

_expect_rejected_in() {
    local scratch="$1" pattern="$2" out status=0
    shift 2
    out="$(as_root env -i PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
        TMPDIR="$scratch" "$@" bash "$install_sh" 2>&1)" || status=$?
    printf '%s\n' "$out"
    if [ "$status" -eq 0 ]; then
        echo "install.sh succeeded; expected a failure" >&2
        return 1
    fi
    if ! printf '%s\n' "$out" | grep -Eq -- "$pattern"; then
        echo "install.sh output doesn't match: ${pattern}" >&2
        return 1
    fi
    if [ -n "$(as_root find "$scratch" -mindepth 1 -print -quit)" ]; then
        echo "install.sh left files in its TMPDIR:" >&2
        as_root find "$scratch" -mindepth 1 >&2
        return 1
    fi
    if [ "$(sha256sum /usr/local/bin/kcadm)" != "$installed_sha" ]; then
        echo "install.sh changed /usr/local/bin/kcadm" >&2
        return 1
    fi
    if ! _no_official_install || ! _no_java; then
        echo "install.sh installed part of the official flavor" >&2
        return 1
    fi
}

check "no pin anywhere fails for the default flavor, naming all three channels" expect_rejected \
    'no pin for CLI_KEYCLOAK: set the version and sha256 feature options, or CLI_KEYCLOAK_VERSION and CLI_KEYCLOAK_SHA256 in the image environment, or in the pins file /etc/devcontainer-features/pins.env'
check "the flavor option wins over CLI_KEYCLOAK_FLAVOR" expect_rejected \
    'flavor official \(from the flavor feature option\)' \
    FLAVOR=official CLI_KEYCLOAK_FLAVOR=rest
check "an invalid flavor option fails" expect_rejected \
    "invalid flavor 'bogus' from the flavor feature option \(expected official or rest\)" \
    FLAVOR=bogus
check "an invalid CLI_KEYCLOAK_FLAVOR in the image environment fails" expect_rejected \
    "invalid flavor 'Rest' from CLI_KEYCLOAK_FLAVOR in the image environment" \
    CLI_KEYCLOAK_FLAVOR=Rest
check "an invalid CLI_KEYCLOAK_FLAVOR in the pins file fails" expect_rejected \
    "invalid flavor 'bogus' from CLI_KEYCLOAK_FLAVOR in the pins file ${flavor_pins}" \
    PINS_FILE="$flavor_pins"
check "a version option without its sha fails" expect_rejected \
    'the feature options set version but not sha256' \
    VERSION="$version"
check "a sha option without the version fails" expect_rejected \
    'the feature options set sha256 but not version' \
    SHA256="$zeros"
check "an image environment version without its sha fails" expect_rejected \
    'the image environment set CLI_KEYCLOAK_VERSION but not CLI_KEYCLOAK_SHA256' \
    CLI_KEYCLOAK_VERSION="$version"
check "an image environment sha without the version fails" expect_rejected \
    'the image environment set CLI_KEYCLOAK_SHA256 but not CLI_KEYCLOAK_VERSION' \
    CLI_KEYCLOAK_SHA256="$zeros"
check "a pins file version without its sha fails" expect_rejected \
    "the pins file ${version_pins} set CLI_KEYCLOAK_VERSION but not CLI_KEYCLOAK_SHA256" \
    PINS_FILE="$version_pins"
check "a malformed sha fails" expect_rejected \
    "sha256 'not-a-sha' is not a sha256" \
    VERSION="$version" SHA256=not-a-sha
check "a version with a leading v fails" expect_rejected \
    "version 'v${version}' must not start with v" \
    VERSION="v${version}" SHA256="$zeros"
check "an install_jre other than true or false fails" expect_rejected \
    "install_jre must be true or false, not 'maybe'" \
    VERSION="$version" SHA256="$zeros" INSTALL_JRE=maybe
check "a wrong sha fails and leaves nothing in TMPDIR" expect_rejected \
    "sha256 mismatch for https://github.com/keycloak/keycloak/releases/download/${version}/keycloak-${version}.tar.gz" \
    VERSION="$version" SHA256="$zeros"

# rest with pins set: a warning, not a failure, listing every pin ignored.
expect_rest_pins_warning() {
    local out status=0
    out="$(as_root env -i PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
        FLAVOR=rest VERSION="$version" CLI_KEYCLOAK_SHA256="$zeros" PINS_FILE="$version_pins" \
        bash "$install_sh" 2>&1)" || status=$?
    printf '%s\n' "$out"
    [ "$status" -eq 0 ] \
        && printf '%s\n' "$out" | grep -Fq "cli-keycloak: warning: the rest flavor downloads nothing, so these pins are ignored: version (feature option), CLI_KEYCLOAK_SHA256 (image environment), CLI_KEYCLOAK_VERSION (pins file ${version_pins})" \
        && [ "$(sha256sum /usr/local/bin/kcadm)" = "$installed_sha" ] \
        && _no_official_install
}
check "rest with pins set warns that they are ignored, and succeeds" expect_rest_pins_warning

rm -f "$version_pins" "$flavor_pins"

# The official flavor's Java check (kcadm-java.sh), run under install.sh's
# shell options against fake javas: small scripts that report a version,
# or fail. No JDK is downloaded.
java_dir="$(mktemp -d)"
fake_java() { # <dir> <script body>
    mkdir -p "$1"
    printf '#!/bin/sh\n%s\n' "$2" >"$1/java"
    chmod 0755 "$1/java"
}
fake_java "${java_dir}/jdk17/bin" 'echo "Property settings:" >&2; echo "    java.specification.version = 17" >&2; echo "openjdk version \"17.0.9\"" >&2'
fake_java "${java_dir}/jdk21/bin" 'echo "    java.specification.version = 21" >&2; echo "openjdk version \"21.0.5\"" >&2'
fake_java "${java_dir}/broken/bin" 'echo "Error: could not create the Java Virtual Machine" >&2; exit 3'
mkdir -p "${java_dir}/path-broken" "${java_dir}/path-21" "${java_dir}/empty-home"
ln -s "${java_dir}/broken/bin/java" "${java_dir}/path-broken/java"
ln -s "${java_dir}/jdk21/bin/java" "${java_dir}/path-21/java"
base_path=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# java_check <install_jre> [VAR=value...]: runs check_kcadm_java in a
# clean environment under set -euo pipefail, called plainly (not in an if
# or ||, so errexit applies inside it), and prints its output, then
# "status=<n>". "reached-end" is printed only if it returned 0 without
# aborting the shell.
cat >"${java_dir}/run-check.sh" <<'EOF'
set -euo pipefail
. "$1"
check_kcadm_java "$2" 21
echo reached-end
EOF
java_check() {
    local install_jre="$1"
    shift
    env -i "$@" bash "${java_dir}/run-check.sh" "${feature_dir}/kcadm-java.sh" "$install_jre" 2>&1 \
        || echo "status=$?"
}

# expect_java <install_jre> <reached-end|status=1> <fixed string> [VAR=value...]
expect_java() {
    local install_jre="$1" outcome="$2" want="$3" out
    shift 3
    out="$(java_check "$install_jre" "$@")"
    printf '%s\n' "$out"
    printf '%s\n' "$out" | grep -Fxq -- "$outcome" \
        && printf '%s\n' "$out" | grep -Fq -- "$want"
}

check "JAVA_HOME with Java 17, install_jre false: warns and succeeds" expect_java false reached-end \
    "cli-keycloak: warning: ${java_dir}/jdk17/bin/java is Java 17; kcadm needs Java 21 or newer at run time (install_jre is false)" \
    PATH="$base_path" JAVA_HOME="${java_dir}/jdk17"
check "JAVA_HOME with Java 17, install_jre true: fails" expect_java true status=1 \
    "cli-keycloak: ${java_dir}/jdk17/bin/java is Java 17; kcadm needs Java 21 or newer" \
    PATH="$base_path" JAVA_HOME="${java_dir}/jdk17"
check "JAVA_HOME wins over java on PATH, as in kcadm.sh" expect_java false reached-end \
    "${java_dir}/jdk17/bin/java is Java 17" \
    PATH="${java_dir}/path-21:${base_path}" JAVA_HOME="${java_dir}/jdk17"
check "JAVA wins over JAVA_HOME, as in kcadm.sh" expect_java true reached-end \
    "cli-keycloak: kcadm will run ${java_dir}/jdk21/bin/java (Java 21)" \
    PATH="$base_path" JAVA="${java_dir}/jdk21/bin/java" JAVA_HOME="${java_dir}/jdk17"
check "java 21 on PATH passes, named by its resolved path" expect_java true reached-end \
    "cli-keycloak: kcadm will run ${java_dir}/jdk21/bin/java (Java 21)" \
    PATH="${java_dir}/path-21:${base_path}"
check "a failing java on PATH, install_jre false: warns, no abort" expect_java false reached-end \
    "cli-keycloak: warning: ${java_dir}/broken/bin/java reports no Java version (it failed or printed none)" \
    PATH="${java_dir}/path-broken:${base_path}"
check "a failing java on PATH, install_jre true: fails with a message" expect_java true status=1 \
    "cli-keycloak: ${java_dir}/broken/bin/java reports no Java version (it failed or printed none); kcadm needs Java 21 or newer" \
    PATH="${java_dir}/path-broken:${base_path}"
check "JAVA_HOME without bin/java is named" expect_java false reached-end \
    "no executable java at ${java_dir}/empty-home/bin/java" \
    PATH="$base_path" JAVA_HOME="${java_dir}/empty-home"
check "no java at all, install_jre false: warns" expect_java false reached-end \
    "warning: no java found (JAVA and JAVA_HOME unset, no java on PATH)" \
    PATH="$base_path"

rm -rf "$java_dir"

reportResults
