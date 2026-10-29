#!/usr/bin/env bash
# Usage: register_link.sh [minutes]   (on the Mac mini; needs cloudflared, python3)
# Serves a one-time "register this device" link: a Profile Service .mobileconfig that makes iOS send
# the device's UDID back here (nothing stays installed). Prints the link, waits for a device, then
# prints "UDID <udid> <product>" and exits. Register it with: gh workflow run build.yml -f udid=...
set -euo pipefail
MINUTES="${1:-20}"
DIR="$(mktemp -d)"; TOKEN="$(openssl rand -hex 16)"
PIDS=()
cleanup() { kill ${PIDS[@]+"${PIDS[@]}"} 2>/dev/null || true; rm -rf "$DIR"; }
trap cleanup EXIT

PORT="$(python3 -I -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')"
# Its own empty config: ~/.cloudflared/config.yml (the named BlueBubbles tunnel) ends in a catch-all
# 404 rule that would otherwise apply to this quick tunnel too.
echo "no-autoupdate: true" >"$DIR/cloudflared.yml"
cloudflared tunnel --config "$DIR/cloudflared.yml" --url "http://127.0.0.1:$PORT" >"$DIR/tunnel.log" 2>&1 & PIDS+=($!)
HOST=""
for _ in $(seq 60); do
  HOST="$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$DIR/tunnel.log" | head -1 || true)"
  [[ -n "$HOST" ]] && break; sleep 1
done
[[ -n "$HOST" ]] || { echo "cloudflared didn't start a tunnel:" >&2; tail -20 "$DIR/tunnel.log" >&2; exit 1; }
BASE="$HOST/$TOKEN"

# Written to a file first: macOS's bash 3.2 loses a here-document fed to a background command.
cat >"$DIR/server.py" <<'PY'
import http.server, re, sys
port, token, base, out, uuid = int(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
PAGE = f"""<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">
<body style="font:19px -apple-system;text-align:center;padding:25vh 24px 0">
<p><a href="{base}/udid.mobileconfig" style="padding:16px 28px;border-radius:14px;background:#fe2c55;color:#fff;text-decoration:none">Register this device for LiquidTok</a></p>
<p style="color:#666">Tap Allow, then Settings &rarr; Profile Downloaded &rarr; Install.</p>"""
DONE = """<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">
<body style="font:22px -apple-system;text-align:center;padding-top:35vh">Registered. You can close this.</body>"""
CONFIG = f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>PayloadContent</key><dict>
    <key>URL</key><string>{base}/udid</string>
    <key>DeviceAttributes</key><array><string>UDID</string><string>PRODUCT</string><string>VERSION</string></array>
  </dict>
  <key>PayloadOrganization</key><string>LiquidTok</string>
  <key>PayloadDisplayName</key><string>LiquidTok device registration</string>
  <key>PayloadDescription</key><string>Sends this device's UDID so LiquidTok can be signed for it. Nothing stays installed.</string>
  <key>PayloadIdentifier</key><string>com.gios.liquidtok.udid</string>
  <key>PayloadUUID</key><string>{uuid}</string>
  <key>PayloadType</key><string>Profile Service</string>
  <key>PayloadVersion</key><integer>1</integer>
</dict></plist>"""

class H(http.server.BaseHTTPRequestHandler):
    def reply(self, code, body=b"", ctype="text/html; charset=utf-8", headers=()):
        self.send_response(code)
        for k, v in headers: self.send_header(k, v)
        self.send_header("Content-Type", ctype); self.send_header("Content-Length", str(len(body)))
        self.end_headers(); self.wfile.write(body)
    def do_GET(self):
        if self.path == f"/{token}/": self.reply(200, PAGE.encode())
        elif self.path == f"/{token}/udid.mobileconfig": self.reply(200, CONFIG.encode(), "application/x-apple-aspen-config")
        elif self.path == f"/{token}/done": self.reply(200, DONE.encode())
        else: self.reply(404)
    def do_POST(self):
        if self.path != f"/{token}/udid": return self.reply(404)
        data = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        udid = re.search(rb"<key>UDID</key>\s*<string>([^<]+)</string>", data)
        product = re.search(rb"<key>PRODUCT</key>\s*<string>([^<]+)</string>", data)
        if udid:
            with open(out, "w") as f:
                f.write(f"UDID {udid.group(1).decode()} {product.group(1).decode() if product else 'unknown'}\n")
        self.reply(301, headers=[("Location", f"{base}/done")])

http.server.HTTPServer(("127.0.0.1", port), H).serve_forever()
PY
UUID="$(uuidgen)"
python3 -I "$DIR/server.py" "$PORT" "$TOKEN" "$BASE" "$DIR/udid" "$UUID" >"$DIR/http.log" 2>&1 & PIDS+=($!)

for _ in $(seq 30); do curl -fsS -o /dev/null "$BASE/" 2>/dev/null && break; sleep 2; done
echo "Registration link, open on the device in Safari: $BASE/"
for _ in $(seq $(( MINUTES * 12 ))); do
  [[ -s "$DIR/udid" ]] && { cat "$DIR/udid"; sleep 60; exit 0; }   # iOS follows the redirect after a delay
  sleep 5
done
echo "No device registered within $MINUTES minutes." >&2; exit 1
