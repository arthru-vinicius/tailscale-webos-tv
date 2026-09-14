#!/bin/sh
set -eu

BASE="/var/lib/webosbrew/tailscale-tv"
HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
TAILSCALE="$HERE/../bin/tailscale"

RUN="$BASE/run"
SOCKET="$RUN/tailscaled.sock"
PIDFILE="$RUN/tailscaled.pid"

echo "== bringing tailscale down =="
if [ -x "$TAILSCALE" ] && [ -S "$SOCKET" ]; then
  "$TAILSCALE" --socket="$SOCKET" down 2>/dev/null || true
fi

echo "== stopping tailscaled =="
if [ -f "$PIDFILE" ]; then
  kill "$(cat "$PIDFILE")" 2>/dev/null || true
  rm -f "$PIDFILE"
fi

killall tailscaled 2>/dev/null || true
sleep 1

echo "== removing interface if still present =="
ip link del tailscale0 2>/dev/null || true

rm -f "$SOCKET"

echo "OK: Tailscale stopped"
