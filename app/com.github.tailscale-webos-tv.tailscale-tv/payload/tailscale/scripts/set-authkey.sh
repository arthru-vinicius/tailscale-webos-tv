#!/bin/sh
set -eu

BASE="/var/lib/webosbrew/tailscale-tv"
KEY="${1:-}"

case "$KEY" in
  tskey-*) : ;;
  *)
    echo "ERROR: does not look like a Tailscale auth key (expected it to start with tskey-)"
    exit 1
    ;;
esac

mkdir -p "$BASE/conf"
printf '%s' "$KEY" > "$BASE/conf/authkey"
chmod 600 "$BASE/conf/authkey"

echo "OK: auth key saved to $BASE/conf/authkey"
echo "Press 'Start' to connect using this key."
