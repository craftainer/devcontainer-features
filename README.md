# devcontainer-features

> [!NOTE]
> This repository is vibe coded with [Claude](https://claude.com/product/claude-code).

craftainer's collection of
[Dev Container Features](https://containers.dev/implementors/features/),
published to `ghcr.io/craftainer/devcontainer-features/<id>`. Each feature
is versioned on its own (see
[ADR 0001](docs/adrs/0001-one-collection-repo-released-with-devcontainers-action.md)).

- **CLI features** (`cli-*`) install a command-line tool at an exact
  version and check every download against a sha256 you supply.
- **Enterprise features** adapt a devcontainer to a corporate network,
  starting with `ssl-ca` for custom root CAs.

A CLI feature takes its version and sha256 from, in order: the feature
option, an `<ID>_*` environment variable in your base image, or a pins file
in your base image. There are no bundled defaults: without a pin the
install fails.

## Features

The feature table and usage details are coming with the first release.

This repo is an instance of
[`template-base`](https://github.com/craftainer/template-base). See
[`docs/TEMPLATE.md`](docs/TEMPLATE.md) for its devcontainer, checks and
template sync.

## License

Licensed under the [GNU General Public License v3.0](LICENSE).
