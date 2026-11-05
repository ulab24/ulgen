#!/usr/bin/env bash
# Hermetic installer test: throwaway GPG key, file:// "release", fake archive. No network, no ~/.gnupg, no real install.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
source "$here/../install.sh"
detect_platform
mk_key() { h="$work/gpg-$1"; mkdir -m 700 "$h"; GNUPGHOME="$h" gpg --batch --quick-generate-key --passphrase '' "$1 <$1@example.invalid>" default default 2>/dev/null; echo "$h"; }
good="$(mk_key release)"; evil="$(mk_key evil)"
GNUPGHOME="$good" gpg --batch --armor --export > "$work/pub.asc"
build() { # version keyhome
  s="$work/stage-$1"; rm -rf "$s"; mkdir -p "$s/engines"
  printf '#!/bin/sh\necho "ulgen %s"\n' "${1#v}" > "$s/ulgen"; echo x > "$s/engines/ulgen-engine-llm"; chmod 755 "$s/ulgen" "$s/engines/"*
  o="$work/rel/releases/download/$1"; mkdir -p "$o"; a="ulgen-$1-$PLAT.tar.gz"
  tar -czf "$o/$a" -C "$s" .; (cd "$o" && sha256sum "$a" > "checksums-$PLAT.txt"); rm -f "$o/checksums-$PLAT.txt.asc"
  GNUPGHOME="$2" gpg --batch --yes --detach-sign --armor -o "$o/checksums-$PLAT.txt.asc" "$o/checksums-$PLAT.txt" 2>/dev/null
}
BASE_URL="file://$work/rel"; PUBKEY_URL="file://$work/pub.asc"; export HOME="$work/home"; mkdir -p "$HOME"
ok() { echo "ok: $1"; }

build v1.0.0 "$good"
VERSION=v1.0.0; BIN_DIR="$work/prefix/bin"
( install_release ) >/dev/null
[ "$("$BIN_DIR/ulgen" version)" = "ulgen 1.0.0" ] && [ -f "$work/prefix/lib/ulgen/engines/ulgen-engine-llm" ] && ok "install + layout"
[ ! -e "$HOME/.gnupg" ] && ok "invoker keyring untouched"

build v1.1.0 "$good"; VERSION=v1.1.0; ( install_release ) >/dev/null
[ "$("$BIN_DIR/ulgen" version)" = "ulgen 1.1.0" ] && ok "update in place"

build v1.2.0 "$evil"; VERSION=v1.2.0
if ( install_release ) >/dev/null 2>&1; then echo "FAIL: wrong signer accepted"; exit 1; fi
[ "$("$BIN_DIR/ulgen" version)" = "ulgen 1.1.0" ] && ok "wrong signer rejected, old install intact"

build v1.3.0 "$good"; echo tamper >> "$work/rel/releases/download/v1.3.0/ulgen-v1.3.0-$PLAT.tar.gz"; VERSION=v1.3.0
if ( install_release ) >/dev/null 2>&1; then echo "FAIL: tampered archive accepted"; exit 1; fi
ok "tampered archive rejected"

if ( parse_args --version=../x ) >/dev/null 2>&1; then echo "FAIL: bad version accepted"; exit 1; fi
ok "bad --version rejected"
echo "all installer tests passed"
