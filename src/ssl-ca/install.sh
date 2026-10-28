#!/usr/bin/env bash
# Installs custom root CA certificates into the system trust store
# (/usr/local/share/ca-certificates, then update-ca-certificates) and into
# every JDK cacerts found, from three sources (see NOTES.md):
#
# - certs: inline PEM, possibly several certificates, with literal
#   newlines or \n escapes;
# - urls plus sha256s: one sha256 per URL, each download checked with
#   il_fetch_verified;
# - *.crt files the consumer's Dockerfile already put in
#   /usr/local/share/ca-certificates, which are kept.
#
# certs, and the urls/sha256s pair, each resolve like a pin (ADR 0002):
# the option, then SSL_CA_<OPTION> in the image environment, then the
# pins file; the first channel that sets a value wins. urls and sha256s
# come from the same channel, as a version and its sha do. With nothing
# supplied and no *.crt present, the install fails. containerEnv (in
# devcontainer-feature.json) points the per-tool CA variables at the
# system bundle this script updates.
set -euo pipefail
# shellcheck source=install-lib.sh
. "$(dirname "$0")/install-lib.sh"

local_dir=/usr/local/share/ca-certificates
bundle=/etc/ssl/certs/ca-certificates.crt

die() {
    printf 'ssl-ca: %s\n' "$*" >&2
    exit 1
}

il_require_root

pins_file="${PINS_FILE:-/etc/devcontainer-features/pins.env}"
if [ -f "$pins_file" ] && [ ! -r "$pins_file" ]; then
    die "pins file ${pins_file} is not readable"
fi

# pins_value <KEY>: prints SSL_CA_<KEY> from the pins file, or nothing.
#
# Reading the pins file relies on install-lib's private _il_pins_get (the
# library has no public single-key getter yet). A library refactor must
# keep it or update this feature; the pins_file_channel scenario fails if
# it breaks.
pins_value() {
    if [ -f "$pins_file" ]; then
        _il_pins_get "$pins_file" "SSL_CA_$1"
    fi
}

# certs: option, then image environment, then pins file.
certs="${CERTS:-}"
certs_from="the certs feature option"
if [ -z "$certs" ] && [ -n "${SSL_CA_CERTS:-}" ]; then
    certs="$SSL_CA_CERTS"
    certs_from="SSL_CA_CERTS in the image environment"
fi
if [ -z "$certs" ]; then
    certs="$(pins_value CERTS)"
    certs_from="SSL_CA_CERTS in the pins file ${pins_file}"
fi

# urls and sha256s: the first channel that sets either supplies both.
urls="" shas="" urls_from=""
if [ -n "${URLS:-}" ] || [ -n "${SHA256S:-}" ]; then
    urls="${URLS:-}" shas="${SHA256S:-}"
    urls_from="the feature options"
    urls_name=urls shas_name=sha256s
elif [ -n "${SSL_CA_URLS:-}" ] || [ -n "${SSL_CA_SHA256S:-}" ]; then
    urls="${SSL_CA_URLS:-}" shas="${SSL_CA_SHA256S:-}"
    urls_from="the image environment"
    urls_name=SSL_CA_URLS shas_name=SSL_CA_SHA256S
else
    urls="$(pins_value URLS)" shas="$(pins_value SHA256S)"
    urls_from="the pins file ${pins_file}"
    urls_name=SSL_CA_URLS shas_name=SSL_CA_SHA256S
fi
if [ -n "$urls" ] && [ -z "$shas" ]; then
    die "${urls_from} set ${urls_name} but not ${shas_name}; set one sha256 per URL in the same place"
fi
if [ -z "$urls" ] && [ -n "$shas" ]; then
    die "${urls_from} set ${shas_name} but not ${urls_name}; set both in one place"
fi
url_list=()
sha_list=()
if [ -n "$urls" ]; then
    read -ra url_list <<<"${urls//[,$'\n\r']/ }"
    read -ra sha_list <<<"${shas//[,$'\n\r']/ }"
    if [ "${#url_list[@]}" -ne "${#sha_list[@]}" ]; then
        die "${urls_from}: ${urls_name} has ${#url_list[@]} URL(s) but ${shas_name} has" \
            "${#sha_list[@]} sha256(s); give exactly one sha256 per URL, in the same order"
    fi
    for i in "${!url_list[@]}"; do
        case "${url_list[$i]}" in
            https://?* | http://?* | file:///?*) ;;
            *) die "${urls_from}: '${url_list[$i]}' in ${urls_name} is not an https://, http:// or file:/// URL" ;;
        esac
        if ! [[ "${sha_list[$i]}" =~ ^[0-9a-fA-F]{64}$ ]]; then
            die "${urls_from}: '${sha_list[$i]}' in ${shas_name} is not a sha256 (64 hex digits)"
        fi
    done
fi

mapfile -t preplaced < <(find -L "$local_dir" -type f -name '*.crt' 2>/dev/null | sort)
if [ -z "$certs" ] && [ "${#url_list[@]}" -eq 0 ] && [ "${#preplaced[@]}" -eq 0 ]; then
    die "no CA certificate given: set the certs option (inline PEM) or the urls and" \
        "sha256s options, or SSL_CA_CERTS / SSL_CA_URLS and SSL_CA_SHA256S in the image" \
        "environment or in the pins file ${pins_file} ($([ -f "$pins_file" ] && echo "has none of them" || echo "not found"))," \
        "or put *.crt files in ${local_dir} in your Dockerfile"
fi

pkgs=()
command -v openssl >/dev/null 2>&1 || pkgs+=(openssl)
command -v update-ca-certificates >/dev/null 2>&1 || pkgs+=(ca-certificates)
if [ "${#pkgs[@]}" -gt 0 ]; then
    il_apt_install "${pkgs[@]}"
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# split_pem <file> <prefix> <what>: writes each PEM certificate block of
# <file> to <prefix>NNN.pem and prints how many there were. Text outside
# the blocks (comments, "subject=" lines) is ignored; any other PEM block
# (a private key above all) or a broken BEGIN/END pairing fails, naming
# only the offending header line, never the content.
split_pem() {
    local out status=0
    out="$(awk -v prefix="$2" '
        { sub(/\r$/, ""); gsub(/^[ \t]+|[ \t]+$/, "") }
        /^-----BEGIN / {
            if (inb) { err = "line " NR ": a BEGIN line inside a certificate block"; exit }
            if ($0 != "-----BEGIN CERTIFICATE-----") { err = "line " NR ": \"" $0 "\" is not a certificate (only CERTIFICATE blocks are accepted)"; exit }
            inb = 1; n++; f = sprintf("%s%03d.pem", prefix, n); print > f; next
        }
        /^-----END / {
            if (!inb || $0 != "-----END CERTIFICATE-----") { err = "line " NR ": \"" $0 "\" does not close a certificate block"; exit }
            print > f; close(f); inb = 0; next
        }
        inb { print > f }
        END {
            if (err == "" && inb) err = "a certificate block has no END line"
            if (err != "") { print err; exit 1 }
            print n + 0
        }' "$1")" || status=$?
    if [ "$status" -ne 0 ]; then
        die "$3: ${out}"
    fi
    printf '%s' "$out"
}

# add_certs <file> <what>: validates every certificate in <file> (PEM, or
# a single DER certificate when allow_der is 1) and stages each, in
# OpenSSL's normalized PEM form, as ${tmp}/new/ssl-ca-<fingerprint>.crt.
add_certs() {
    local file="$1" what="$2" allow_der="${3:-0}" n i pem dir
    split_seq=$((split_seq + 1))
    dir="${tmp}/split-${split_seq}"
    mkdir "$dir"
    if ! grep -q -- '-----BEGIN ' "$file"; then
        if [ "$allow_der" = 1 ] && openssl x509 -inform DER -in "$file" -out "${dir}/001.pem" 2>/dev/null; then
            stage_cert "${dir}/001.pem" "$what"
            return
        fi
        if [ "$allow_der" = 1 ]; then
            die "${what}: neither PEM (no -----BEGIN CERTIFICATE-----) nor a DER certificate"
        fi
        die "${what}: no PEM certificate (-----BEGIN CERTIFICATE-----) found"
    fi
    n="$(split_pem "$file" "${dir}/" "$what")"
    [ "$n" -gt 0 ] || die "${what}: no PEM certificate (-----BEGIN CERTIFICATE-----) found"
    for ((i = 1; i <= n; i++)); do
        printf -v pem '%s/%03d.pem' "$dir" "$i"
        stage_cert "$pem" "${what}, certificate ${i} of ${n}"
    done
}

# stage_cert <pem> <what>: validates one certificate and stages it.
stage_cert() {
    local pem="$1" what="$2" fp subject
    if ! openssl x509 -in "$pem" -out "${pem}.norm" 2>"${tmp}/openssl.err"; then
        die "${what} is not a valid X.509 certificate: $(head -c 300 "${tmp}/openssl.err")"
    fi
    fp="$(fingerprint "${pem}.norm")"
    subject="$(openssl x509 -in "${pem}.norm" -noout -subject -nameopt RFC2253)"
    if ! openssl x509 -in "${pem}.norm" -noout -checkend 0 >/dev/null; then
        echo "ssl-ca: warning: ${what} (${subject}) has expired" >&2
    fi
    install -D -m 0644 "${pem}.norm" "${tmp}/new/ssl-ca-${fp:0:16}.crt"
    echo "ssl-ca: ${what}: ${subject}, sha256 fingerprint ${fp}"
}

# fingerprint <pem>: prints the certificate's sha256 fingerprint as 64
# lower-case hex digits.
fingerprint() {
    local fp
    fp="$(openssl x509 -in "$1" -noout -fingerprint -sha256)" || die "cannot fingerprint $1"
    fp="${fp#*=}"
    fp="${fp//:/}"
    printf '%s' "${fp,,}"
}

split_seq=0
if [ -n "$certs" ]; then
    # \n escapes, as from a single-line ${localEnv:...} or pins-file value.
    printf '%s\n' "${certs//\\n/$'\n'}" >"${tmp}/certs.pem"
    add_certs "${tmp}/certs.pem" "$certs_from"
fi
for i in "${!url_list[@]}"; do
    il_fetch_verified "${url_list[$i]}" "${sha_list[$i]}" "${tmp}/url-${i}"
    add_certs "${tmp}/url-${i}" "${url_list[$i]}" 1
done
for f in "${preplaced[@]}"; do
    # Validated, not staged: they stay where the consumer put them.
    # update-ca-certificates skips (with only a warning) a .crt that isn't
    # exactly one PEM certificate, so anything else fails here.
    split_seq=$((split_seq + 1))
    n="$(split_pem "$f" "${tmp}/pre-${split_seq}-" "$f")"
    case "$n" in
        0) die "${f}: no PEM certificate (-----BEGIN CERTIFICATE-----) found; update-ca-certificates reads PEM only" ;;
        1) ;;
        *) die "${f} holds ${n} certificates; update-ca-certificates skips a .crt file unless it holds exactly one, so split it" ;;
    esac
    openssl x509 -in "${tmp}/pre-${split_seq}-001.pem" -noout 2>/dev/null \
        || die "${f} is not a valid X.509 certificate"
    echo "ssl-ca: keeping ${f}"
done

install -d -m 0755 "$local_dir"
if [ -d "${tmp}/new" ]; then
    for f in "${tmp}/new"/*.crt; do
        install -m 0644 "$f" "${local_dir}/$(basename "$f")"
    done
fi
update-ca-certificates || die "update-ca-certificates failed"

# Every certificate in ${local_dir} (staged or pre-placed), one per file,
# for the bundle check and the Java import.
mapfile -t installed < <(find -L "$local_dir" -type f -name '*.crt' | sort)
all_dir="${tmp}/all"
mkdir "$all_dir"
for f in "${installed[@]}"; do
    split_seq=$((split_seq + 1))
    split_pem "$f" "${all_dir}/${split_seq}-" "$f" >/dev/null
done
# Compared without any whitespace, so line wrapping and indentation in a
# pre-placed file don't matter.
bundle_flat="$(tr -d ' \t\n\r' <"$bundle")"
for pem in "$all_dir"/*.pem; do
    body="$(openssl x509 -in "$pem" | tr -d ' \t\n\r')"
    if [[ "$bundle_flat" != *"$body"* ]]; then
        die "$(openssl x509 -in "$pem" -noout -subject) is not in ${bundle} after update-ca-certificates"
    fi
done
echo "ssl-ca: ${bundle} holds all $(find "$all_dir" -name '*.pem' | wc -l) certificate(s) from ${local_dir}"

# Java: import into every cacerts found, through the JDK's own keytool.
# Several JDKs often share one store (Debian links each JDK's cacerts to
# /etc/ssl/certs/java/cacerts), so stores are deduplicated by their real
# path. A certificate already in a store (same sha256 fingerprint, under
# any alias; Debian's ca-certificates-java hook adds ours on
# update-ca-certificates) is skipped, so a re-run changes nothing.
declare -A store_keytool=()
store_order=()
shopt -s nullglob
for cacerts in /usr/lib/jvm/*/lib/security/cacerts /usr/lib/jvm/*/jre/lib/security/cacerts \
    ${JAVA_HOME:+"${JAVA_HOME}/lib/security/cacerts" "${JAVA_HOME}/jre/lib/security/cacerts"}; do
    [ -e "$cacerts" ] || continue
    real="$(readlink -f "$cacerts")"
    [ -f "$real" ] || continue
    [ -z "${store_keytool[$real]+x}" ] || continue
    jdk="${cacerts%/lib/security/cacerts}"
    keytool=""
    for candidate in "${jdk}/bin/keytool" "${jdk%/jre}/bin/keytool"; do
        if [ -x "$candidate" ]; then
            keytool="$candidate"
            break
        fi
    done
    if [ -z "$keytool" ]; then
        keytool="$(command -v keytool || true)"
    fi
    if [ -z "$keytool" ]; then
        echo "ssl-ca: warning: no keytool for ${cacerts}; not importing into it" >&2
        continue
    fi
    store_keytool[$real]="$keytool"
    store_order+=("$real")
done
shopt -u nullglob

for store in "${store_order[@]}"; do
    keytool="${store_keytool[$store]}"
    # changeit is the JDK's documented default password for cacerts.
    # -v lists every entry's SHA256 fingerprint (plain -list shows only
    # SHA-1 on Java 8).
    listing="$("$keytool" -list -v -keystore "$store" -storepass changeit 2>&1)" \
        || die "keytool (${keytool}) cannot read ${store} with the default password changeit: ${listing:0:300}"
    listing="${listing^^}"
    added=0 present=0
    for pem in "$all_dir"/*.pem; do
        fp="$(fingerprint "$pem")"
        fp_colons="$(sed 's/../&:/g; s/:$//' <<<"${fp^^}")"
        if [[ "$listing" == *"$fp_colons"* ]]; then
            present=$((present + 1))
            continue
        fi
        "$keytool" -importcert -noprompt -trustcacerts -alias "ssl-ca-${fp:0:16}" \
            -file "$pem" -keystore "$store" -storepass changeit >/dev/null \
            || die "keytool (${keytool}) cannot import $(openssl x509 -in "$pem" -noout -subject) into ${store}"
        # The same certificate can sit in ${local_dir} twice (pre-placed
        # and also passed in certs); a second import under the same alias
        # would fail, so it now counts as present.
        listing+=" ${fp_colons}"
        added=$((added + 1))
    done
    echo "ssl-ca: ${store} (keytool ${keytool}): ${added} imported, ${present} already present"
done

echo "ssl-ca: done; the trust store is ${bundle}"
