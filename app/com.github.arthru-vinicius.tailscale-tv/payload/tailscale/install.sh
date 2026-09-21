#!/bin/sh
set -eu

APPID="com.github.arthru-vinicius.tailscale-tv"
DST="/var/lib/webosbrew/tailscale-tv"
INIT_FILE="/var/lib/webosbrew/init.d/90-tailscale-tv"

find_appdir() {
  for d in \
    "/media/developer/apps/usr/palm/applications/$APPID" \
    "/media/cryptofs/apps/usr/palm/applications/$APPID" \
    "/media/internal/apps/usr/palm/applications/$APPID"
  do
    if [ -d "$d/payload/tailscale" ]; then
      echo "$d"
      return 0
    fi
  done

  find /media -type d -path "*/applications/$APPID" 2>/dev/null | head -1
}

APPDIR="$(find_appdir)"
SRC="$APPDIR/payload/tailscale"

echo "== preparing Tailscale state =="
echo "APPDIR=$APPDIR"
echo "SRC=$SRC"
echo "DST=$DST"

echo
echo "== payload contents =="
find "$SRC" -maxdepth 4 -type f -print 2>/dev/null || true

echo
echo "== detecting CPU architecture =="
ARCH="$(uname -m)"
echo "uname -m: $ARCH"
case "$ARCH" in
  aarch64|arm64)
    SRC_BIN="tailscale.combined.arm64"
    ;;
  armv7l|armv6l|arm)
    SRC_BIN="tailscale.combined.armv7"
    ;;
  *)
    echo "ERROR: unsupported architecture '$ARCH' (no matching build in this package)"
    exit 1
    ;;
esac

echo
echo "== restoring executable bits =="
# IPKs packaged on Windows carry no executable bit (files arrive as 0666),
# so restore it here, before the checks below.
chmod 755 "$SRC/install.sh" "$SRC"/scripts/*.sh "$SRC"/bin/tailscale.combined.* 2>/dev/null || true

echo
echo "== checking binaries =="
if [ ! -x "$SRC/bin/$SRC_BIN" ]; then
  echo "ERROR: missing executable $SRC/bin/$SRC_BIN"
  exit 1
fi

echo
echo "== checking scripts =="
for f in start.sh stop.sh status.sh set-authkey.sh autostart.sh boot.sh uninstall.sh; do
  if [ ! -x "$SRC/scripts/$f" ]; then
    echo "ERROR: missing executable $SRC/scripts/$f"
    exit 1
  fi
done

mkdir -p "$DST" "$DST/conf" "$DST/state" "$DST/run"
chmod 700 "$DST/conf" "$DST/state"

AUTOSTART_WAS_ENABLED=0
if [ -e "$INIT_FILE" ] || [ -L "$INIT_FILE" ]; then
  AUTOSTART_WAS_ENABLED=1
fi

echo
echo "== stopping old runtime before migrating =="
if [ -x "$DST/scripts/stop.sh" ]; then
  sh "$DST/scripts/stop.sh" 2>&1 || true
fi

echo
echo "== linking packaged components =="
rm -rf "$DST/bin" "$DST/scripts"
mkdir -p "$DST/bin"
ln -sfn "$SRC/bin/$SRC_BIN" "$DST/bin/tailscale"
ln -sfn "$SRC/bin/$SRC_BIN" "$DST/bin/tailscaled"
ln -s "$SRC/scripts" "$DST/scripts"
echo "bin/tailscale, bin/tailscaled -> $SRC/bin/$SRC_BIN"
echo "scripts -> $SRC/scripts"

echo
echo "== packaged binary version =="
"$DST/bin/tailscale" --version 2>&1 || true

if [ "$AUTOSTART_WAS_ENABLED" -eq 1 ]; then
  echo
  echo "== migrating autostart hook =="
  "$SRC/scripts/autostart.sh" enable
fi

echo
echo "OK: state prepared and packaged components linked"
echo "Next: use 'Save auth key' to store your Tailscale auth key, then 'Start'."
