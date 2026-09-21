#!/bin/sh
set -eu

BASE="/var/lib/webosbrew/tailscale-tv"
HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
TAILSCALED="$HERE/../bin/tailscaled"
TAILSCALE="$HERE/../bin/tailscale"

STATE_DIR="$BASE/state"
RUN="$BASE/run"
SOCKET="$RUN/tailscaled.sock"
PIDFILE="$RUN/tailscaled.pid"
LOGFILE="$RUN/tailscaled.log"
AUTHKEY_FILE="$BASE/conf/authkey"

mkdir -p "$STATE_DIR" "$RUN"

[ -x "$TAILSCALED" ] || { echo "ERROR: missing $TAILSCALED"; exit 1; }
[ -x "$TAILSCALE" ] || { echo "ERROR: missing $TAILSCALE"; exit 1; }

if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  echo "tailscaled already running (pid $(cat "$PIDFILE"))"
else
  echo "== starting tailscaled =="
  rm -f "$SOCKET"
  "$TAILSCALED" \
    --state="$STATE_DIR/tailscaled.state" \
    --socket="$SOCKET" \
    >"$LOGFILE" 2>&1 &
  echo $! > "$PIDFILE"

  echo "== waiting for tailscaled socket =="
  i=0
  while [ ! -S "$SOCKET" ]; do
    i=$((i + 1))
    if [ "$i" -ge 20 ]; then
      echo "ERROR: tailscaled socket did not appear after 20s"
      echo "== tailscaled.log =="
      cat "$LOGFILE" 2>/dev/null || true
      exit 1
    fi
    sleep 1
  done
fi

echo
echo "== checking login state =="
BACKEND_STATE="$("$TAILSCALE" --socket="$SOCKET" status --json 2>/dev/null \
  | sed -n 's/.*"BackendState": *"\([^"]*\)".*/\1/p')"
echo "BackendState: ${BACKEND_STATE:-unknown}"

if [ "$BACKEND_STATE" != "Running" ]; then
  if [ -f "$AUTHKEY_FILE" ]; then
    echo
    echo "== authenticating with saved auth key =="
    "$TAILSCALE" --socket="$SOCKET" up --auth-key="file:$AUTHKEY_FILE"
  else
    echo "ERROR: not authenticated and no auth key saved."
    echo "Use 'Save auth key' first (see console.tailscale.com/admin/settings/keys)."
    exit 1
  fi
fi

echo
echo "== status =="
"$TAILSCALE" --socket="$SOCKET" status
echo
ip addr show tailscale0 2>/dev/null || echo "tailscale0 interface not up yet"

echo
echo "OK: Tailscale started"
