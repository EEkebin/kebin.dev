#!/usr/bin/env python3
"""Tiny reachability endpoint for the kebin.dev homepage.

GET /api/status?svc=<name>  ->  HTML fragment: <span class="dot up"></span>online
Only reports up/down. Never exposes versions, errors, or anything from the backend.
Results are cached per service for CACHE_SECONDS so page views cannot hammer the media VM.
"""
import ssl
import sys
import time
import threading
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

LISTEN = ("127.0.0.1", 8765)
TIMEOUT = 3
CACHE_SECONDS = 30
MEDIA = "http://10.0.10.30"

SERVICES = {
    "stream": f"{MEDIA}:8096/health",
    "seerr":  f"{MEDIA}:5055/api/v1/status",
    "music":  f"{MEDIA}:4533/ping",
    "files":  f"{MEDIA}:8090/",
    "cloud":  f"{MEDIA}:8081/status.php",
    "code":   "http://10.0.10.100:4096/",
    "comfy":  "http://10.0.10.100:8188/system_stats",
    "pve":    "https://10.0.0.200:8006/",
}

_cache = {}
_lock = threading.Lock()


def probe(url):
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "kebin-status/1"})
        ctx = None
        if url.startswith("https://10."):  # internal self-signed endpoints (Proxmox)
            ctx = ssl.create_default_context(); ctx.check_hostname = False; ctx.verify_mode = ssl.CERT_NONE
        with urllib.request.urlopen(req, timeout=TIMEOUT, context=ctx) as r:
            return r.status < 500
    except Exception:
        return False


def status(svc):
    now = time.time()
    with _lock:
        hit = _cache.get(svc)
        if hit and now - hit[0] < CACHE_SECONDS:
            return hit[1]
    up = probe(SERVICES[svc])
    with _lock:
        _cache[svc] = (now, up)
    return up


class Handler(BaseHTTPRequestHandler):
    server_version = "kebin-status/1"

    def log_message(self, *_):
        pass

    def do_GET(self):
        u = urlparse(self.path)
        svc = parse_qs(u.query).get("svc", [""])[0]
        if u.path != "/api/status" or svc not in SERVICES:
            self.send_response(404)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        up = status(svc)
        body = ('<span class="dot up"></span>online' if up else '<span class="dot down"></span>offline').encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--check":
        for name in SERVICES:
            print(f"{name:7} {'online' if status(name) else 'offline'}")
        sys.exit(0)
    ThreadingHTTPServer(LISTEN, Handler).serve_forever()
