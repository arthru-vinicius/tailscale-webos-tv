#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
APP_ID="com.github.tailscale-webos-tv.tailscale-tv"
VERSION="0.1.0"
APP="$ROOT/app/$APP_ID"
IPK="$ROOT/dist/${APP_ID}_${VERSION}_all.ipk"
MANIFEST="$ROOT/dist/$APP_ID.manifest.json"

test -f "$IPK" || { echo "ERROR: missing $IPK" >&2; exit 1; }
test -f "$MANIFEST" || { echo "ERROR: missing $MANIFEST" >&2; exit 1; }

# README.md is deliberately excluded: it credits the reference project.
if grep -R -n -E 'cfernande1470|webos-wireguard|org\.webosbrew\.wireguard' \
  "$APP" "$ROOT/$APP_ID.manifest.json"; then
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

# Members are extracted with `ar x` rather than piped out with `ar p`: MinGW's
# ar writes stdout in text mode on Windows, which corrupts the gzip streams.
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
(cd "$WORK" && ar x "$IPK")
DATA="$WORK/data.tar.gz"
DATA_LIST="$(tar tzf "$DATA")"

CONTROL="$(tar xzOf "$WORK/control.tar.gz" control)"
echo "$CONTROL" | grep -qx "Package: $APP_ID"
echo "$CONTROL" | grep -qx "Version: $VERSION"
echo "$CONTROL" | grep -qx 'Architecture: all'
echo "$CONTROL" | grep -Eq '^Maintainer: .+ <[^>]+@[^>]+>$'

if ar tv "$IPK" | grep -q ' 1970 '; then
  echo "ERROR: deterministic ar timestamps are rejected by LG appinstalld" >&2
  exit 1
fi

echo "$DATA_LIST" | grep -q "^usr/palm/applications/$APP_ID/appinfo.json$"
echo "$DATA_LIST" | grep -q "^usr/palm/applications/$APP_ID/icon.png$"
echo "$DATA_LIST" | grep -q "^usr/palm/applications/$APP_ID/payload/tailscale/scripts/boot.sh$"
echo "$DATA_LIST" | grep -q "^usr/palm/applications/$APP_ID/payload/tailscale/bin/tailscale.combined.armv7$"
echo "$DATA_LIST" | grep -q "^usr/palm/applications/$APP_ID/payload/tailscale/bin/tailscale.combined.arm64$"
echo "$DATA_LIST" | grep -q "^usr/palm/packages/$APP_ID/packageinfo.json$"
tar xzOf "$DATA" "usr/palm/applications/$APP_ID/appinfo.json" | grep -q "\"id\": \"$APP_ID\""
grep -q "\"id\": \"$APP_ID\"" "$MANIFEST"
grep -q "${APP_ID}_${VERSION}_all.ipk" "$MANIFEST"

# Non-fatal: install.sh restores the bits on the TV, but a release IPK should
# ship with them so the boot hook survives an app update.
if tar tvzf "$DATA" \
  | grep -E 'payload/tailscale/(install\.sh|scripts/[^/]+\.sh|bin/tailscale\.combined\.[a-z0-9]+)$' \
  | grep -qv '^-..x'; then
  echo "WARNING: some packaged scripts/binaries lack the executable bit (typical when packaging on Windows)." >&2
  echo "         install.sh restores it on the TV; build the release IPK on Linux/WSL/CI to ship it correctly." >&2
fi

echo "Release verification passed for $APP_ID $VERSION"
