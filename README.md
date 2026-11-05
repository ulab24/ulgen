# ulgen

ulgen runs open-weight models locally from one binary, the way Ollama does: text, image and speech-to-text today,
on macOS (Apple silicon) and Linux. Models come from a fixed, verified allowlist and are checked by hash before use.
`ulgen serve` listens on loopback only and needs a bearer token; `ulgen mcp` exposes the models to MCP clients.

This repository carries only what you need to install ulgen: the install script, the release signing key, and the
released binaries with their signed checksums. Development happens on ulab24's own infrastructure, so there is no
source here. **This is the place to tell us what you think** (open an issue).

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/ulab24/ulgen/main/install.sh | bash
```

Installs the latest release for your machine (linux-amd64, linux-arm64 or darwin-arm64). The download is verified
before anything is installed: the checksum list must carry a valid signature from the ulab24 release key, and the
archive must match it. `gpg` is required for that; without it the installer stops (set `ULGEN_INSTALL_SKIP_GPG=1`
to accept sha256 only, which does not prove who published the archive).

The `ulgen` command goes to `/usr/local/bin` as root, otherwise `~/.local/bin`; its program files and engines go to
the sibling `lib/ulgen`. Re-run the command to update; your models and configuration are not touched.

```sh
curl -fsSL https://raw.githubusercontent.com/ulab24/ulgen/main/install.sh | bash -s -- --version=v0.1.0
curl -fsSL https://raw.githubusercontent.com/ulab24/ulgen/main/install.sh | bash -s -- --dir=$HOME/bin
```

## Docker

```sh
docker pull ghcr.io/ulab24/ulgen:latest
docker run --rm -i -v ulgen-data:/data ghcr.io/ulab24/ulgen:latest mcp
docker run --rm --network host -v ulgen-data:/data ghcr.io/ulab24/ulgen:latest serve
```

CPU engines only. The API listens on loopback inside the container by design, so use `--network host` (Linux) to reach it.

## Verify by hand

```sh
gpg --import ulab24-release-signing-key.asc
gpg --verify checksums-linux-amd64.txt.asc checksums-linux-amd64.txt
sha256sum --check --ignore-missing checksums-linux-amd64.txt
```

## First run

```sh
ulgen doctor                              # checks the install and the engines
ulgen pull qwen/qwen2.5-0.5b-instruct     # downloads and verifies the model
ulgen run qwen/qwen2.5-0.5b-instruct "hello"
```

Every release also signs its engine binaries; `ulgen doctor` should print `release verification: on`.
