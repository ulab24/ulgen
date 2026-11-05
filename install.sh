#!/usr/bin/env bash
# ulgen -- installer.
#
#   curl -fsSL https://raw.githubusercontent.com/ulab24/ulgen/main/install.sh | bash
#
# Installs the latest ulgen release, or updates an existing install in place. It only downloads signed, checksummed
# release archives from this repository's GitHub Releases; ulgen's source lives on ulab24's own infrastructure.
#
# Layout: LIB_DIR/ulgen and LIB_DIR/engines/ stay together (ulgen finds its engines beside itself), and BIN_DIR/ulgen
# is a symlink to LIB_DIR/ulgen.
set -euo pipefail

BASE_URL="${ULGEN_INSTALL_BASE_URL:-https://github.com/ulab24/ulgen}"
PUBKEY_URL="${ULGEN_INSTALL_PUBKEY_URL:-https://raw.githubusercontent.com/ulab24/ulgen/main/ulab24-release-signing-key.asc}"
VERSION="latest"
BIN_DIR=""
PLAT=""   # linux-amd64 | linux-arm64 | darwin-arm64 (the names the release archives use)

if [ -t 1 ]; then c_bold=$'\033[1m'; c_red=$'\033[31m'; c_yellow=$'\033[33m'; c_reset=$'\033[0m'
else c_bold=""; c_red=""; c_yellow=""; c_reset=""; fi
log()  { printf '%s\n' "$*"; }
warn() { printf '%s%s%s\n' "$c_yellow" "$*" "$c_reset" >&2; }
die()  { printf '%s%s%s\n' "$c_red" "$*" "$c_reset" >&2; exit 1; }

usage() {
  cat <<'USAGE'
Usage: install.sh [--version=vX.Y.Z] [--dir=PATH] [--help]

  --version=vX.Y.Z   Version to install. Default: the latest release.
  --dir=PATH         Directory that gets the `ulgen` command. Default: where an existing ulgen on PATH lives, else
                     /usr/local/bin as root, else ~/.local/bin. The program files go in a sibling "lib/ulgen".
  --help             Show this help.

Re-run the installer to update. Your models and configuration are never touched.
USAGE
}

parse_args() {
  dir_given=0
  for arg in "$@"; do
    case "$arg" in
      --version=*) VERSION="${arg#*=}" ;;
      --dir=*) BIN_DIR="${arg#*=}"; dir_given=1 ;;
      --help) usage; exit 0 ;;
      *) die "unknown argument: $arg (see --help)" ;;
    esac
  done
  if [ "$VERSION" != "latest" ] && ! [[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
    die "--version must look like v1.2.3 or v1.2.3-rc.1, got: $VERSION"
  fi
  if [ "$dir_given" -eq 1 ] && [ -z "$BIN_DIR" ]; then die "--dir must not be empty"; fi
}

detect_platform() {
  os="$(uname -s)"; machine="$(uname -m)"
  case "$os/$machine" in
    Linux/x86_64|Linux/amd64) PLAT=linux-amd64 ;;
    Linux/aarch64|Linux/arm64) PLAT=linux-arm64 ;;
    Darwin/arm64|Darwin/aarch64) PLAT=darwin-arm64 ;;
    *) die "no ulgen build for $os/$machine (published: linux-amd64, linux-arm64, darwin-arm64)" ;;
  esac
}

resolve_latest() {
  [ "$VERSION" = "latest" ] || return 0
  case "$BASE_URL" in https://*) : ;; *) die "cannot look up the latest release from $BASE_URL; pass --version=vX.Y.Z" ;; esac
  effective="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "$BASE_URL/releases/latest" 2>/dev/null || true)"
  tag="${effective##*/tag/}"
  if [ "$tag" != "$effective" ] && [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then VERSION="$tag"
  else die "could not find the latest release at $BASE_URL/releases/latest (none published yet, or no network); pass --version=vX.Y.Z"; fi
}

download_url() { printf '%s/releases/download/%s/%s' "$BASE_URL" "$VERSION" "$1"; }
fetch() { curl -fsSL "$1" -o "$2"; }

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  else die "need sha256sum or shasum to verify the download"; fi
}

# verify_checksums DIR NAME... : downloads checksums-<plat>.txt(.asc) into DIR, verifies the PGP signature against the
# ulab24 release key in a throwaway keyring, then checks the sha256 of every NAME. gpg is required (it is the only thing
# that proves who published the archive); ULGEN_INSTALL_SKIP_GPG=1 downgrades to checksum-only, loudly.
verify_checksums() {
  dir="$1"; shift
  sums="checksums-$PLAT.txt"
  fetch "$(download_url "$sums")" "$dir/$sums"
  fetch "$(download_url "$sums.asc")" "$dir/$sums.asc"
  if command -v gpg >/dev/null 2>&1; then
    keyring="$(mktemp -d)"
    if fetch "$PUBKEY_URL" "$dir/ulab24-release-signing-key.asc"; then
      gpg --batch --homedir "$keyring" --import "$dir/ulab24-release-signing-key.asc" >/dev/null 2>&1 || true
      verified=0
      if gpg --batch --homedir "$keyring" --verify "$dir/$sums.asc" "$dir/$sums" >/dev/null 2>&1; then verified=1; fi
      gpgconf --homedir "$keyring" --kill all >/dev/null 2>&1 || true
      rm -rf "$keyring"
      [ "$verified" -eq 1 ] || die "$sums failed GPG signature verification -- refusing to install"
      log "$sums signature: OK"
    else
      rm -rf "$keyring"; die "could not fetch the release signing key -- refusing to install without signature verification"
    fi
  elif [ "${ULGEN_INSTALL_SKIP_GPG:-}" = 1 ]; then
    warn "gpg not found -- ULGEN_INSTALL_SKIP_GPG=1 set, checking sha256 only (this does NOT prove who published it)"
  else
    die "gpg not found. Install gnupg to verify the release signature, or set ULGEN_INSTALL_SKIP_GPG=1 to accept sha256 only."
  fi
  for name in "$@"; do
    want="$(awk -v f="$name" '$2==f {print $1}' "$dir/$sums")"
    [ -n "$want" ] || die "$sums has no entry for $name"
    got="$(sha256_of "$dir/$name")"
    [ "$want" = "$got" ] || die "checksum mismatch for $name -- refusing to install"
  done
}

existing_bin_dir() {
  found="$(command -v ulgen 2>/dev/null || true)"
  [ -n "$found" ] && [ -x "$found" ] || return 0
  dirname "$found"
}

choose_dir() {
  [ -z "$BIN_DIR" ] || return 0
  current="$(existing_bin_dir)"
  if [ -n "$current" ]; then
    if [ -w "$current" ]; then BIN_DIR="$current"; return 0; fi
    die "ulgen is installed in $current, which this user cannot write. Re-run with sudo, or pass --dir=PATH for a second copy."
  fi
  if [ "$(id -u)" -eq 0 ]; then BIN_DIR=/usr/local/bin; else BIN_DIR="$HOME/.local/bin"; fi
}

install_release() {
  WORK="$(mktemp -d)"
  trap 'rm -rf "$WORK"' EXIT
  archive="ulgen-${VERSION}-${PLAT}.tar.gz"
  log "downloading ulgen $VERSION ($PLAT)..."
  fetch "$(download_url "$archive")" "$WORK/$archive" \
    || die "could not download $archive from $BASE_URL (is $VERSION a published release?)"
  verify_checksums "$WORK" "$archive"

  mkdir -p "$WORK/unpacked"
  tar -xzf "$WORK/$archive" -C "$WORK/unpacked"
  [ -f "$WORK/unpacked/ulgen" ] && [ -d "$WORK/unpacked/engines" ] || die "$archive does not have the expected layout"

  choose_dir
  LIB_DIR="$(dirname "$BIN_DIR")/lib/ulgen"
  mkdir -p "$BIN_DIR" "$(dirname "$LIB_DIR")" 2>/dev/null || die "cannot create $BIN_DIR or $(dirname "$LIB_DIR") (try sudo, or pass --dir=PATH)"
  [ -w "$BIN_DIR" ] && [ -w "$(dirname "$LIB_DIR")" ] || die "cannot write to $BIN_DIR or $(dirname "$LIB_DIR") (try sudo, or pass --dir=PATH)"

  before=""
  [ ! -x "$LIB_DIR/ulgen" ] || before="$("$LIB_DIR/ulgen" version 2>/dev/null || true)"

  # Stage next to the destination, then swap directories, so an interrupted install never leaves a half-updated tree.
  stage="$LIB_DIR.new.$$"; old="$LIB_DIR.old.$$"
  rm -rf "$stage"; mkdir -p "$stage"
  cp -R "$WORK/unpacked/." "$stage/"
  chmod -R go-w "$stage"; chmod 0755 "$stage" "$stage/engines" "$stage/ulgen"
  [ ! -e "$LIB_DIR" ] || mv "$LIB_DIR" "$old"
  mv "$stage" "$LIB_DIR"
  rm -rf "$old"
  ln -sfn "$LIB_DIR/ulgen" "$BIN_DIR/ulgen"

  after="$("$LIB_DIR/ulgen" version 2>/dev/null || echo "ulgen $VERSION")"
  log ""
  if [ -n "$before" ] && [ "$before" != "$after" ]; then log "${c_bold}ulgen updated:${c_reset} $before -> $after ($BIN_DIR)"
  elif [ -n "$before" ]; then log "${c_bold}ulgen reinstalled:${c_reset} $after ($BIN_DIR)"
  else log "${c_bold}ulgen installed:${c_reset} $after ($BIN_DIR)"; fi
  case ":$PATH:" in *":$BIN_DIR:"*) : ;; *) warn "$BIN_DIR is not on your PATH. Add it, for example:  export PATH=\"$BIN_DIR:\$PATH\"" ;; esac
  log "Next: run 'ulgen doctor'."
}

main() { parse_args "$@"; detect_platform; resolve_latest; log "version: $VERSION"; install_release; }

if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then main "$@"; fi
