#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
APP_ID="com.github.arthru-vinicius.tailscale-tv"
VERSION="0.1.0"
APP="$ROOT/app/$APP_ID"
IPK="$ROOT/dist/${APP_ID}_${VERSION}_all.ipk"
MANIFEST="$ROOT/dist/$APP_ID.manifest.json"

test -f "$IPK" || { echo "ERROR: missing $IPK" >&2; exit 1; }
test -f "$MANIFEST" || { echo "ERROR: missing $MANIFEST" >&2; exit 1; }

if grep -R -n -E 'cfernande1470|webos-wireguard|org\.webosbrew\.wireguard' \
  "$APP" "$ROOT/README.md" "$ROOT/$APP_ID.manifest.json"; then
  echo "ERROR: leftover reference-project text found" >&2
  exit 1
fi

desc_armv7="$(file "$APP/payload/tailscale/bin/tailscale.combined.armv7")"
echo "$desc_armv7"
echo "$desc_armv7" | grep -q 'ELF 32-bit LSB.*ARM' || {
  echo "ERROR: tailscale.combined.armv7 is not a 32-bit ARM ELF" >&2
  exit 1
}

desc_arm64="$(file "$APP/payload/tailscale/bin/tailscale.combined.arm64")"
echo "$desc_arm64"
echo "$desc_arm64" | grep -q 'ELF 64-bit LSB.*ARM aarch64' || {
  echo "ERROR: tailscale.combined.arm64 is not an ARM aarch64 ELF" >&2
  exit 1
}

for script in "$APP/payload/tailscale/install.sh" "$APP/payload/tailscale/scripts/"*.sh; do
  sh -n "$script"
done

test -x "$APP/payload/tailscale/scripts/boot.sh"

if grep -R -n -E 'TAILSCALED?="\$BASE/bin/' "$APP/payload/tailscale/scripts"; then
  echo "ERROR: packaged binaries must be resolved relative to their scripts, not \$BASE/bin directly" >&2
  exit 1
fi

CONTROL="$(ar p "$IPK" control.tar.gz | tar xzO control)"
echo "$CONTROL" | grep -qx "Package: $APP_ID"
echo "$CONTROL" | grep -qx "Version: $VERSION"
echo "$CONTROL" | grep -qx 'Architecture: all'
echo "$CONTROL" | grep -Eq '^Maintainer: .+ <[^>]+@[^>]+>$'

if ar tv "$IPK" | grep -q ' 1970 '; then
  echo "ERROR: deterministic ar timestamps are rejected by LG appinstalld" >&2
  exit 1
fi

ar p "$IPK" data.tar.gz | tar tzf - | grep -q "^usr/palm/applications/$APP_ID/appinfo.json$"
ar p "$IPK" data.tar.gz | tar tzf - | grep -q "^usr/palm/applications/$APP_ID/payload/tailscale/scripts/boot.sh$"
ar p "$IPK" data.tar.gz | tar tzf - | grep -q "^usr/palm/packages/$APP_ID/packageinfo.json$"
ar p "$IPK" data.tar.gz | tar xzO "usr/palm/applications/$APP_ID/appinfo.json" | grep -q "\"id\": \"$APP_ID\""
grep -q "\"id\": \"$APP_ID\"" "$MANIFEST"
grep -q "${APP_ID}_${VERSION}_all.ipk" "$MANIFEST"

echo "Release verification passed for $APP_ID $VERSION"
