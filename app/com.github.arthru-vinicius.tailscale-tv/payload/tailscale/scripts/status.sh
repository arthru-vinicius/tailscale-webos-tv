#!/bin/sh

BASE="/var/lib/webosbrew/tailscale-tv"
HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
TAILSCALE="$HERE/../bin/tailscale"
SOCKET="$BASE/run/tailscaled.sock"

echo "== process =="
ps | grep tailscaled | grep -v grep || echo "tailscaled not running"

echo
echo "== interface =="
ip addr show tailscale0 2>/dev/null || echo "tailscale0 does not exist"

echo
echo "== tailscale status =="
if [ -S "$SOCKET" ]; then
  "$TAILSCALE" --socket="$SOCKET" status 2>&1 || true
else
  echo "socket not found: $SOCKET"
fi

echo
echo "== relevant routes =="
ip route | grep -E "tailscale0|default" || ip route

echo
echo "== log (last 40 lines) =="
tail -40 "$BASE/run/tailscaled.log" 2>/dev/null || true
