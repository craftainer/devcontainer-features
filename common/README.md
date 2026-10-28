# common

`install-lib.sh` is the shared library of this collection's `install.sh`
scripts: root and arch checks, pin resolution from the option, the image
environment or the pins file (`il_resolve_pin`, `il_resolve_version`),
sha256-verified downloads (`il_fetch_verified`), apt installs, including a
third-party repository with a fingerprint-pinned key (`il_apt_add_repo`,
`il_apt_install_pinned`), and installing a binary or a per-user state
directory (`il_install_bin`, `il_user_state_dir`). Its header and the
comment above each function are the reference.

- **Never sourced from here.** A feature folder is packaged and published
  on its own, so nothing outside it is available at install time. Each
  `src/<id>/` carries a byte-identical copy as `install-lib.sh`, which its
  `install.sh` sources.
- **Change it here, then copy it.** Edit only `common/install-lib.sh`, then
  run `cp common/install-lib.sh src/<id>/install-lib.sh` for every feature
  that has a copy, and bump each of those features' `version` (a change
  under `src/<id>/` ships only with a new version).
- **The drift hook.** `scripts/check-install-lib-drift.sh` (a prek hook)
  fails when a copy differs from this file, or when an `install.sh` sources
  `install-lib.sh` but its folder has no copy.
- **Pin rules.** Pin resolution follows
  [ADR 0002](../docs/adrs/0002-resolve-pins-from-option-env-or-pins-file-with-no-defaults.md)
  and the apt-installed CLIs
  [ADR 0003](../docs/adrs/0003-pin-apt-installed-clis-by-upstream-version-with-a-verified-repo-key.md).
