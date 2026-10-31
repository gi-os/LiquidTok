#!/usr/bin/env bash
# Usage: dump_receiver.sh [minutes]   (on the Mac mini; needs cloudflared, python3)
# Starts a write-only receiver for a diagnostic build's layout dumps behind a Cloudflare quick tunnel and
# prints the URL to pass as the build workflow's dump_url input:
#   gh workflow run build.yml -R gi-os/LiquidTok -f dump_url=<url>
# Dumps land in /tmp/lt-dumps (one text file per screen/pose change). Stops after [minutes] (default 180).
set -euo pipefail
MINUTES="${1:-180}"
HERE="$(cd "$(dirname "$0")" && pwd)"
DIR="$(mktemp -d)"; OUT=/tmp/lt-dumps; mkdir -p "$OUT"
PIDS=()
trap 'kill "${PIDS[@]}" 2>/dev/null; rm -rf "$DIR"' EXIT
TOKEN="$(python3 -I -c 'import secrets; print(secrets.token_hex(16))')"
PORT="$(python3 -I -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')"
python3 -I "$HERE/dump_receiver.py" "$PORT" "$TOKEN" "$OUT" >"$DIR/recv.log" 2>&1 & PIDS+=($!)
# Its own empty config, like install_link.sh (~/.cloudflared/config.yml is a named tunnel with a catch-all).
echo "no-autoupdate: true" >"$DIR/cloudflared.yml"
cloudflared tunnel --config "$DIR/cloudflared.yml" --url "http://127.0.0.1:$PORT" >"$DIR/tunnel.log" 2>&1 & PIDS+=($!)
HOST=""
for _ in $(seq 1 30); do
  HOST="$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$DIR/tunnel.log" | head -1 || true)"
  [[ -n "$HOST" ]] && break; sleep 2
done
[[ -n "$HOST" ]] || { echo "cloudflared didn't start a tunnel:" >&2; tail -20 "$DIR/tunnel.log" >&2; exit 1; }
echo "$HOST/$TOKEN/dump" > "$OUT/.url"
echo "Dump URL (for dump_url): $HOST/$TOKEN/dump"
echo "Dumps go to $OUT; stopping in $MINUTES min."
sleep "$((MINUTES * 60))"
