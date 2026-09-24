#!/usr/bin/env python3
"""Tiny reachability endpoint for the kebin.dev pages.

GET /api/status?svc=<name>    ->  <span class="dot up"></span>online
GET /api/status?group=<name>  ->  <span class="dot up"></span>7/7 online   (dot: up = all, part = some, down = none)
Only reports up/down. Never exposes versions, errors, or anything from the backend.
Results are cached per service for CACHE_SECONDS so page views cannot hammer the VMs.
"""
import ssl
import sys
import time
import threading
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

LISTEN = ("127.0.0.1", 8765)
TIMEOUT = 3
CACHE_SECONDS = 30
MEDIA = "http://10.0.10.30"
AI = "http://10.0.10.100"

SERVICES = {
    # media
    "stream":      f"{MEDIA}:8096/health",
    "seerr":       f"{MEDIA}:5055/api/v1/status",
    "music":       f"{MEDIA}:4533/ping",
    "files":       f"{MEDIA}:8090/",
    "cloud":       f"{MEDIA}:8081/status.php",
    "vr":          f"{MEDIA}:8000/health",
    # arr stack
    "sonarr":      f"{MEDIA}:8989/ping",
    "radarr":      f"{MEDIA}:7878/ping",
    "lidarr":      f"{MEDIA}:8686/ping",
    "prowlarr":    f"{MEDIA}:9696/ping",
    "bazarr":      f"{MEDIA}:6767/",
    "qbittorrent": f"{MEDIA}:8080/",
    "tdarr":       f"{MEDIA}:8265/",
    # ai
    "code":        f"{AI}:4096/",
    "comfy":       f"{AI}:8188/system_stats",
    "search":      f"{AI}:8888/healthz",
    "models":      f"{AI}:8080/running",
    # system
    "pve":         "https://10.0.0.200:8006/",
    "auth":        f"{AI}:3000/",
}

GROUPS = {
    "arr":    ["sonarr", "radarr", "lidarr", "prowlarr", "bazarr", "qbittorrent", "tdarr"],
    "media":  ["stream", "seerr", "music", "files", "cloud", "vr"],
    "ai":     ["code", "comfy", "search", "models"],
    "system": ["pve", "auth"],
}
GROUPS["media-all"] = GROUPS["media"] + GROUPS["arr"]   # the home page card for Media counts the arr stack too

_cache = {}
_lock = threading.Lock()
_pool = ThreadPoolExecutor(max_workers=8)


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


def group_status(name):
    members = GROUPS[name]
    ups = sum(1 for r in _pool.map(status, members) if r)
    cls = "up" if ups == len(members) else ("down" if ups == 0 else "part")
    return f'<span class="dot {cls}"></span>{ups}/{len(members)} online'


class Handler(BaseHTTPRequestHandler):
    server_version = "kebin-status/1"

    def log_message(self, *_):
        pass

    def do_GET(self):
        u = urlparse(self.path)
        q = parse_qs(u.query)
        svc = q.get("svc", [""])[0]
        group = q.get("group", [""])[0]
        if u.path != "/api/status" or not (svc in SERVICES or group in GROUPS):
            self.send_response(404)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if group:
            body = group_status(group).encode()
        else:
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
            print(f"{name:12} {'online' if status(name) else 'offline'}")
        for name in GROUPS:
            print(f"{name:12} {group_status(name)}")
        sys.exit(0)
    ThreadingHTTPServer(LISTEN, Handler).serve_forever()
