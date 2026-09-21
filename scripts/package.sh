#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
APP_ID="com.github.arthru-vinicius.tailscale-tv"
VERSION="0.1.0"
APP="$ROOT/app/$APP_ID"
DIST="$ROOT/dist"
PACKAGER="${ARES_PACKAGE:-ares-package}"
IPK="$DIST/${APP_ID}_${VERSION}_all.ipk"

command -v "$PACKAGER" >/dev/null 2>&1 || {
  echo "ERROR: ares-package is required." >&2
  echo "Install @webos-tools/cli or webosbrew/ares-cli-rs, or set ARES_PACKAGE to its path." >&2
  exit 1
}

mkdir -p "$DIST"
rm -f "$IPK"

# ares-cli-rs supports --force-arch; LG's @webos-tools/cli does not (and
# already emits "all" for a web app without native services).
FORCE_ARCH=""
if "$PACKAGER" --help 2>&1 | grep -q -- '--force-arch'; then
  FORCE_ARCH="--force-arch all"
fi

# shellcheck disable=SC2086
"$PACKAGER" $FORCE_ARCH --outdir "$DIST" "$APP"

test -f "$IPK" || {
  echo "ERROR: ares-package did not create $IPK" >&2
  exit 1
}

cp "$ROOT/$APP_ID.manifest.json" "$DIST/$APP_ID.manifest.json"

echo "Created $IPK"
echo "Created $DIST/$APP_ID.manifest.json"
