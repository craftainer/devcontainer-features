## What it does

`ssl-ca` adds your organization's root CA certificates (for example the CA
of a TLS-inspecting proxy) to the container's trust store:

1. It checks all its inputs first: a malformed URL list (a bad scheme, a
   bad sha, a different number of URLs and shas) fails before anything is
   downloaded or installed.
2. It checks the inline certificates and the pre-placed `*.crt` files
   with `openssl x509`, writes the new ones to
   `/usr/local/share/ca-certificates/ssl-ca-<fingerprint>.crt`, named by
   the first 16 hex digits of the certificate's sha256 fingerprint, so a
   re-run doesn't duplicate them, and keeps the files already in that
   directory. Then it runs `update-ca-certificates`, which rebuilds the
   system bundle `/etc/ssl/certs/ca-certificates.crt` and the hashed
   directory `/etc/ssl/certs`.
3. Only then does it fetch the URLs, so their https connections already
   trust the CAs from step 2 (see "Behind a TLS-intercepting proxy"). It
   checks and installs those certificates the same way and runs
   `update-ca-certificates` again, then checks every certificate made it
   into the bundle.
4. It imports every certificate in `/usr/local/share/ca-certificates`
   into each JDK's `cacerts` it finds (see "Java").
5. Through `containerEnv` it points the usual per-tool CA variables at the
   system bundle (see "Environment variables").

With no certificate from any source the install fails, naming all of
them. There are no bundled certificates.

## Supplying certificates

The `certs` value, and the `urls` / `sha256s` pair, are each taken from
the first of these places that sets them: the feature option, then
`SSL_CA_CERTS` / `SSL_CA_URLS` / `SSL_CA_SHA256S` in your image's
environment, then the same keys in the pins file. `urls` and `sha256s`
always come from the same place: a URL list in one place is never paired
with shas from another. Inline certificates, URLs and pre-placed files can
be combined; all of them are installed.

### Inline PEM (`certs`)

One or more PEM certificates (`-----BEGIN CERTIFICATE-----` blocks). Text
between the blocks is ignored; any other PEM block, such as a private key,
fails the install without echoing it. Line breaks can be literal newlines
or `\n` escapes, so both of these work:

```jsonc
"features": {
  "ghcr.io/craftainer/devcontainer-features/ssl-ca:1": {
    // the host's CORP_CA_PEM, with real newlines or \n escapes
    "certs": "${localEnv:CORP_CA_PEM}"
  }
}
```

```sh
# on the host, e.g. in your shell profile
export CORP_CA_PEM="$(cat ~/corp-root-ca.pem)"
```

In a Dockerfile `ENV` or a pins file the value has to fit on one line, so
use `\n` escapes there (quoted in the pins file):

```dockerfile
ENV SSL_CA_CERTS='-----BEGIN CERTIFICATE-----\nMIIB...\n-----END CERTIFICATE-----'
```

```sh
# pins.env: one line, generated with
#   printf 'SSL_CA_CERTS="%s"\n' "$(awk '{ printf "%s\\n", $0 }' corp-root-ca.pem)" >>pins.env
SSL_CA_CERTS="-----BEGIN CERTIFICATE-----\nMIIB...\n-----END CERTIFICATE-----\n"
```

### A URL and its sha256 (`urls`, `sha256s`)

Each URL is downloaded with the collection's checked fetch and must match
its sha256, given in the same order. Separate entries with commas or
blanks; a different number of URLs and shas fails. A URL may serve one or
more PEM certificates, or one DER certificate (`.cer`). `https://`,
`http://` (many internal PKIs publish their CA certificates over plain
http) and `file:///` URLs are accepted: the sha256 you pin is what makes
the download trustworthy, whatever the scheme.

```jsonc
"ghcr.io/craftainer/devcontainer-features/ssl-ca:1": {
  "urls": "https://pki.example.com/root-ca.pem, http://pki.example.com/issuing-ca.cer",
  "sha256s": "<sha256 of root-ca.pem> <sha256 of issuing-ca.cer>"
}
```

Get each sha with `curl -fsSL <url> | sha256sum` and check it against
what your PKI team publishes. Fetching a URL needs `curl`, which the
install adds if it is missing.

**Behind a TLS-intercepting proxy.** The URLs are fetched after the
inline (`certs`) and pre-placed certificates are already in the system
trust store, and curl checks the download's TLS connection against that
store. So if the proxy re-signs https traffic, supply the proxy's CA
through `certs` or a pre-placed `.crt`, and the https URLs (for your other
internal CAs, say) download through it. A proxy CA that is itself only
reachable through one of the `urls` can't be trusted in time for its own
download: use `http://`, `file:///`, `certs` or a pre-placed file for that
one.

That ordering doesn't cover the packages `ssl-ca` itself needs first.
When `openssl` or `ca-certificates` is missing, it installs them with apt
before any of your CAs is trusted, so if the image's apt sources are https
behind the intercepting proxy, that install fails. Start from an image
that already has `openssl` and `ca-certificates`, or whose apt sources the
proxy doesn't intercept. (`curl`, when `urls` need it, is installed after
the inline and pre-placed CAs are trusted, so a proxy CA given through
`certs` or a pre-placed `.crt` already covers that install.)

### A certificate already in your image

Copy the certificate into `/usr/local/share/ca-certificates/` (or a
subdirectory) in the Dockerfile your devcontainer builds from, and give
the feature no options. Each file must end in `.crt` and hold exactly one
PEM certificate, as `update-ca-certificates` requires; anything else fails
the install rather than being skipped.

```dockerfile
COPY corp-root-ca.pem /usr/local/share/ca-certificates/corp-root-ca.crt
```

```jsonc
"build": { "dockerfile": "Dockerfile" },
"features": {
  "ghcr.io/craftainer/devcontainer-features/ssl-ca:1": {}
}
```

### The pins file

The pins file is `/etc/devcontainer-features/pins.env` unless the
`pins_file` option names another path. It is parsed, not sourced, and can
hold the pins of every feature in this collection; `ssl-ca` reads only
`SSL_CA_CERTS`, `SSL_CA_URLS` and `SSL_CA_SHA256S`. If the `pins_file`
option names a file that doesn't exist, the install prints a warning (a
typo or a missing `COPY` is the usual cause), even when the options or the
image environment supply the certificates.

```sh
# pins.env
SSL_CA_URLS="https://pki.example.com/root-ca.pem"
SSL_CA_SHA256S="<sha256 of root-ca.pem>"
```

## Install order

**List `ssl-ca` first in `overrideFeatureInstallOrder`.** Features install
in an order the Dev Container CLI chooses, and a feature that downloads
something (every `cli-*` feature in this collection, and most others)
needs your CA trusted before it runs when it sits behind a TLS-inspecting
proxy:

```jsonc
"features": {
  "ghcr.io/craftainer/devcontainer-features/ssl-ca:1": {
    "certs": "${localEnv:CORP_CA_PEM}"
  },
  "ghcr.io/craftainer/devcontainer-features/cli-s5cmd:1": {}
},
"overrideFeatureInstallOrder": [
  "ghcr.io/craftainer/devcontainer-features/ssl-ca"
]
```

Features not listed there keep their own order after the listed ones.

Why the collection doesn't do this for you: a feature can't force itself
to install first
([vscode-remote-release#7150](https://github.com/microsoft/vscode-remote-release/issues/7150)),
and the only lever a feature has, `installsAfter`, makes the Dev Container
CLI fetch the named feature from ghcr.io on every build, even for
consumers who don't use `ssl-ca`. That would break the air-gapped and
proxied networks this feature exists for, so no feature here declares it.
`ssl-ca` itself declares none either: it is the one the others must
follow.

The Dev Container CLI turns a feature's `containerEnv` into `ENV` lines
just before that feature's install step, so the variables below are also
set while every later feature installs (and while `ssl-ca` itself runs),
but not for features that ran earlier. The same `ENV` lines replace any
value your image already set: a `CURL_CA_BUNDLE` or `SSL_CERT_FILE` from
your Dockerfile's `ENV` is overridden with the system bundle, both for
`ssl-ca`'s own URL downloads and in the built image. To point a tool at a
different bundle, set the variable at run time in your `devcontainer.json`
(`containerEnv` or `remoteEnv`), which takes precedence over the image's
`ENV`; that changes what the running container uses, not what `ssl-ca`'s
downloads used at build time.

## Environment variables

`ssl-ca` sets these in `containerEnv`, each pointing at the system bundle
`/etc/ssl/certs/ca-certificates.crt` unless noted:

| Variable | Read by | Notes |
| --- | --- | --- |
| `SSL_CERT_FILE` | OpenSSL and everything built on it (Python `ssl`, Ruby, Go, Bun, uv, ...) | A file. |
| `SSL_CERT_DIR` | the same | `/etc/ssl/certs`, the hashed directory `update-ca-certificates` maintains. |
| `REQUESTS_CA_BUNDLE` | Python `requests` | Replaces certifi's bundle. |
| `CURL_CA_BUNDLE` | the `curl` command (and `requests`, as a fallback) | Not read by libcurl in other programs. |
| `PIP_CERT` | pip (`--cert`) | |
| `NODE_EXTRA_CA_CERTS` | Node.js, Bun, Claude Code | Added to the bundled roots; read once at process start. |
| `NODE_USE_SYSTEM_CA` | Node.js (on Linux since 23.9), Bun | `1`: also trust the system store, which on Linux means `SSL_CERT_FILE` / `SSL_CERT_DIR` (else `/etc/ssl/cert.pem` and `/etc/ssl/certs`). Older Node ignores it, so `NODE_EXTRA_CA_CERTS` covers those. |
| `AWS_CA_BUNDLE` | AWS CLI and SDKs | |
| `GIT_SSL_CAINFO` | git over https | Overrides `http.sslCAInfo`. |
| `CARGO_HTTP_CAINFO` | cargo | Overrides `http.cainfo`. |
| `DENO_CERT` | Deno | Added to Deno's default (Mozilla) store. |
| `UV_SYSTEM_CERTS` | uv 0.11.0 and later | `1`: use the platform's store instead of uv's bundled Mozilla roots. uv also honours `SSL_CERT_FILE`, which overrides both uv switches. |
| `UV_NATIVE_TLS` | uv | The same switch under its older name, which uv documents as deprecated in favour of `UV_SYSTEM_CERTS`; still set because uv before 0.11.0 reads only this one. |

The variables are static, so they are set even when the bundle doesn't
contain your CA yet; that only happens if the install failed, which stops
the build.

## Java

Every certificate in `/usr/local/share/ca-certificates` is imported into
each `cacerts` keystore found at `/usr/lib/jvm/*/lib/security/cacerts`
(and `.../jre/lib/security/cacerts`) and under `$JAVA_HOME`, with that
JDK's own `keytool` and the JDK's default store password `changeit`. JDKs
that share one store (Debian and Ubuntu link every packaged JDK's
`cacerts` to `/etc/ssl/certs/java/cacerts`) are handled once, and a
certificate already in a store (same sha256 fingerprint, under any alias)
is skipped, so a re-run changes nothing. New entries get the alias
`ssl-ca-<fingerprint>`. With no JDK present this step is skipped silently;
a store `keytool` can't open with `changeit` fails the install.

A JDK installed **after** `ssl-ca` isn't covered by this step. A Debian or
Ubuntu packaged JDK (`default-jre-headless`, `openjdk-*`) still gets the
certificates: its `ca-certificates-java` dependency builds
`/etc/ssl/certs/java/cacerts` from `/etc/ssl/certs`, where
`update-ca-certificates` has already linked them (checked on `debian:13`:
`default-jre-headless` installed after `ssl-ca` lists the CA in
`keytool -cacerts`). A JDK from elsewhere,
such as the `ghcr.io/devcontainers/features/java` feature (SDKMAN) or a
tarball, brings its own `cacerts`: install it before `ssl-ca`, or import
the CA yourself.

## What isn't covered

- **Alpine** and other non-Debian images: Debian and Ubuntu, amd64 and
  arm64, only.
- **Tools with their own bundled store that ignore the variables above**,
  for example some Electron apps, Firefox/NSS databases, and statically
  linked binaries with an embedded root list. Point them at
  `/etc/ssl/certs/ca-certificates.crt` with their own setting.
- **A JDK installed after `ssl-ca`** that doesn't use Debian's
  `ca-certificates-java` (see "Java").
- **Certificates added at run time.** The trust store is built into the
  image; to change it, change the input and rebuild.

## OS support

Debian and Ubuntu, on amd64 and arm64. The install adds `openssl` and
`ca-certificates` if either is missing, and `curl` when `urls` are given.
