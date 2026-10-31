#!/usr/bin/env python3
# Usage: dump_receiver.py <port> <token> <outdir>
# Write-only endpoint for a diagnostic LiquidTok build's layout dumps (Debug.x, LT_DUMP_URL): accepts
# POST /<token>/dump, stores the body as a text file in <outdir>, answers nothing else.
import http.server, os, sys, time

PORT, TOKEN, OUT = int(sys.argv[1]), sys.argv[2], sys.argv[3]
MAX_BODY, MAX_FILES = 4 * 1024 * 1024, 400
os.makedirs(OUT, exist_ok=True)


class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path != f"/{TOKEN}/dump":
            return self.send_error(404)
        size = int(self.headers.get("Content-Length") or 0)
        count = len(os.listdir(OUT))
        if size <= 0 or size > MAX_BODY or count >= MAX_FILES:
            return self.send_error(413)
        body = self.rfile.read(size)
        reason = "".join(c for c in (self.headers.get("X-LT-Reason") or "dump")[:16] if c.isalnum())
        with open(os.path.join(OUT, f"{time.strftime('%H%M%S')}-{count:03d}-{reason}.txt"), "wb") as f:
            f.write(body)
        self.send_response(204)
        self.end_headers()

    def do_GET(self):
        self.send_error(404)

    def log_message(self, *args):
        pass


http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
