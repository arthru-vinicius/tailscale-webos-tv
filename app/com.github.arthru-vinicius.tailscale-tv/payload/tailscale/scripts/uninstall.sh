#!/bin/sh
set -eu

BASE="/var/lib/webosbrew/tailscale-tv"
HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
TAILSCALE="$HERE/../bin/tailscale"
SOCKET="$BASE/run/tailscaled.sock"

echo "== logging out of the tailnet (removes this node from your account) =="
if [ -x "$TAILSCALE" ] && [ -S "$SOCKET" ]; then
  "$TAILSCALE" --socket="$SOCKET" logout 2>/dev/null || true
fi

echo "== stopping processes =="
"$HERE/stop.sh" 2>/dev/null || true
killall tailscaled 2>/dev/null || true

echo "== cleaning interface =="
ip link del tailscale0 2>/dev/null || true

echo "== removing autostart =="
rm -f /var/lib/webosbrew/init.d/90-tailscale-tv

echo "== removing runtime data and auth key =="
rm -rf "$BASE"

echo
echo "OK: Tailscale runtime removed"
echo "You can now uninstall the app from Homebrew Channel."
