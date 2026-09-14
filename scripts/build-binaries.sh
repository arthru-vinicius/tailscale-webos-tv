#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
APPID="com.github.arthru-vinicius.tailscale-tv"
APP="$ROOT/app/$APPID"
BIN="$APP/payload/tailscale/bin"
TAILSCALE_REF="${TAILSCALE_REF:-}"

command -v go >/dev/null 2>&1 || {
  echo "ERROR: Go is required" >&2
  exit 1
}

mkdir -p "$BIN"

CHECKOUT="$ROOT/.build/tailscale-src"
if [ ! -d "$CHECKOUT" ]; then
  echo "== cloning tailscale/tailscale =="
  mkdir -p "$ROOT/.build"
  git clone --depth 1 https://github.com/tailscale/tailscale "$CHECKOUT"
fi

if [ -n "$TAILSCALE_REF" ]; then
  echo "== checking out $TAILSCALE_REF =="
  (cd "$CHECKOUT" && git fetch --depth 1 origin "$TAILSCALE_REF" && git checkout FETCH_HEAD)
fi

# Two architectures are bundled in the same package because the target TV's
# CPU is not known ahead of time for a public release. install.sh picks the
# right one on the TV itself, based on `uname -m` (see section 12 of the
# original handoff doc: this must be confirmed per device, not assumed).

echo "== building tailscale.combined for linux/arm (ARMv7, 32-bit) =="
(
  cd "$CHECKOUT"
  GOOS=linux GOARCH=arm GOARM=7 CGO_ENABLED=0 \
    ./build_dist.sh --extra-small -o "$BIN/tailscale.combined.armv7" tailscale.com/cmd/tailscaled
)

echo "== building tailscale.combined for linux/arm64 =="
(
  cd "$CHECKOUT"
  GOOS=linux GOARCH=arm64 CGO_ENABLED=0 \
    ./build_dist.sh --extra-small -o "$BIN/tailscale.combined.arm64" tailscale.com/cmd/tailscaled
)

chmod 755 "$BIN/tailscale.combined.armv7" "$BIN/tailscale.combined.arm64"
file "$BIN/tailscale.combined.armv7" "$BIN/tailscale.combined.arm64"

echo
echo "OK: binaries built in $BIN"
echo "install.sh selects the right one at install time via 'uname -m' on the TV."
