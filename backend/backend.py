#!/usr/bin/env python3
"""Tiny REST backend for the CN project.  Usage: python3 backend.py A 3001"""
import hashlib
import json
import sys
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

NAME = sys.argv[1] if len(sys.argv) > 1 else "A"
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 3001

INFO_BODY = json.dumps({
    "team": "team1",
    "project": "Private Network Service Platform",
    "note": "This response is cacheable for 60 seconds",
}).encode()
INFO_ETAG = '"' + hashlib.sha256(INFO_BODY).hexdigest()[:16] + '"'


class Handler(BaseHTTPRequestHandler):
    server_version = "TeamBackend/1.0"

    def reply(self, code, body=b"", headers=None):
        self.send_response(code)
        self.send_header("X-Backend", NAME)
        for key, value in (headers or {}).items():
            self.send_header(key, value)
        if code != 304:
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if code != 304 and self.command != "HEAD":
            self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/":
            body = json.dumps({"service": "team1 backend", "backend": NAME,
                               "message": f"Backend {NAME} is running"}).encode()
            self.reply(200, body, {"Cache-Control": "no-store"})
        elif path == "/api/status":
            body = json.dumps({"backend": NAME, "status": "ok",
                               "time": datetime.now(timezone.utc).isoformat()}).encode()
            self.reply(200, body, {"Cache-Control": "no-store"})
        elif path == "/api/info":
            cache = {"Cache-Control": "public, max-age=60", "ETag": INFO_ETAG}
            if self.headers.get("If-None-Match") == INFO_ETAG:
                self.reply(304, headers=cache)
            else:
                self.reply(200, INFO_BODY, cache)
        else:
            self.reply(404, json.dumps({"error": "not found", "backend": NAME}).encode())

    do_HEAD = do_GET


if __name__ == "__main__":
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    print(f"Backend {NAME} listening on 0.0.0.0:{PORT}  (Ctrl+C to stop)")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nstopped")
