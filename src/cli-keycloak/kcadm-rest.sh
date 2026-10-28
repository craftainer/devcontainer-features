#!/usr/bin/env bash
# kcadm METHOD PATH [JSON]: a small client for the Keycloak Admin REST API,
# installed as /usr/local/bin/kcadm by the cli-keycloak feature's rest
# flavor. Ported from craftainer/template-fastapi's
# scripts/develop.d/40-kcadm.sh; see this feature's NOTES.md for usage.
#
# It logs in to the master realm as KEYCLOAK_ADMIN (password grant,
# admin-cli client) at KEYCLOAK_URL, then sends one request with the
# token. The password, the token and the body never appear in a process's
# arguments: they reach curl through stdin or a header file in a private
# temporary directory. A JSON reply is pretty-printed, anything else is
# printed as it is; a non-2xx reply goes to stderr and exits 1.
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 || $2 != /* ]]; then
    echo "Usage: kcadm METHOD PATH [JSON_BODY]" >&2
    echo "Example: kcadm GET /admin/realms/master/users" >&2
    exit 1
fi

missing=()
for var in KEYCLOAK_URL KEYCLOAK_ADMIN KEYCLOAK_ADMIN_PASSWORD; do
    [[ -n "${!var:-}" ]] || missing+=("$var")
done
if [[ ${#missing[@]} -gt 0 ]]; then
    echo "kcadm: set ${missing[*]} (KEYCLOAK_URL, KEYCLOAK_ADMIN and KEYCLOAK_ADMIN_PASSWORD are required)" >&2
    exit 1
fi

method=$1
path=$2
base_url=${KEYCLOAK_URL%/}

umask 077
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# show <file> [>&2]: prints <file> pretty-printed if it is JSON, else as
# it is. Parsing is checked first, so a failed write while pretty-printing
# never falls back to printing the body a second time.
show() {
    [[ -s "$1" ]] || return 0
    if python3 -I -c 'import json, sys; json.load(open(sys.argv[1], "rb"))' "$1" 2>/dev/null; then
        python3 -I -m json.tool --no-ensure-ascii "$1"
    else
        cat "$1"
        [[ -z "$(tail -c 1 "$1")" ]] || echo
    fi
}

# Log in. printf is a builtin, so the password is in no argv.
status=0
code=$(printf '%s' "$KEYCLOAK_ADMIN_PASSWORD" | curl -sS -o "${tmp}/login" -w '%{http_code}' \
    "${base_url}/realms/master/protocol/openid-connect/token" \
    --data-urlencode grant_type=password \
    --data-urlencode client_id=admin-cli \
    --data-urlencode "username=${KEYCLOAK_ADMIN}" \
    --data-urlencode password@-) || status=$?
if [[ $status -ne 0 ]]; then
    echo "kcadm: login request to ${base_url} failed (curl exit ${status})" >&2
    exit 1
fi
if [[ $code != 2?? ]]; then
    echo "kcadm: login failed: HTTP ${code}" >&2
    show "${tmp}/login" >&2
    exit 1
fi
# The token goes straight from the reply into a header file.
if ! python3 -I -c '
import json, sys
token = json.load(open(sys.argv[1]))["access_token"]
with open(sys.argv[2], "w") as f:
    f.write("Authorization: Bearer " + token + "\n")
' "${tmp}/login" "${tmp}/auth" 2>/dev/null; then
    echo "kcadm: login reply has no access_token:" >&2
    show "${tmp}/login" >&2
    exit 1
fi

curl_args=(-sS -o "${tmp}/body" -w '%{http_code}' -X "$method" \
    -H @"${tmp}/auth" \
    -H "Content-Type: application/json" \
    "${base_url}${path}")
status=0
if [[ $# -eq 3 ]]; then
    # From stdin with --data-binary, so the body is sent byte for byte and
    # a leading @ is never read as a file name.
    code=$(printf '%s' "$3" | curl "${curl_args[@]}" --data-binary @-) || status=$?
else
    code=$(curl "${curl_args[@]}") || status=$?
fi
if [[ $status -ne 0 ]]; then
    echo "kcadm: ${method} ${path} failed (curl exit ${status})" >&2
    exit 1
fi
if [[ $code != 2?? ]]; then
    echo "kcadm: ${method} ${path}: HTTP ${code}" >&2
    show "${tmp}/body" >&2
    exit 1
fi
show "${tmp}/body"
