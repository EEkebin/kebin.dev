#!/usr/bin/env python3
"""Un-stall torrents whose only sources are web seeds (archive.org). Run by media-qb-webseed.timer every 5 min.

archive.org answers every file request with a redirect to a data node, and those nodes return the odd
"500 Internal Server Error". libtorrent then remembers the original seed as not having that file and the
torrent sits in "stalled" forever, even though the server is fine a minute later (seen 2026-10-06..09).
Removing and re-adding the torrent's web seed URLs resets that memory without restarting qBittorrent.
Prints one line per kicked torrent, nothing otherwise."""
import json, re, sys, time, urllib.request, urllib.parse, http.cookiejar

B = "http://127.0.0.1:8080"
pw = re.search(r'^QBT_PASSWORD=(.*)$', open("/srv/media/.env").read(), re.M).group(1).strip().strip('"\'')
op = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))

def call(path, data=None):
    body = urllib.parse.urlencode(data).encode() if data else None
    with op.open(urllib.request.Request(B + path, data=body, headers={"Referer": B}), timeout=60) as r:
        text = r.read().decode()
    try: return json.loads(text)
    except ValueError: return text

if call("/api/v2/auth/login", {"username": "admin", "password": pw}) != "Ok.":
    sys.exit("qbittorrent login failed")
for t in call("/api/v2/torrents/info?filter=stalled_downloading"):
    urls = [w["url"] for w in call(f"/api/v2/torrents/webseeds?hash={t['hash']}")]
    if not urls:
        continue
    joined = "|".join(urllib.parse.quote(u, safe="") for u in urls)
    call("/api/v2/torrents/removeWebSeeds", {"hash": t["hash"], "urls": joined})
    call("/api/v2/torrents/addWebSeeds", {"hash": t["hash"], "urls": joined})
    print(f"{time.strftime('%Y-%m-%dT%H:%M:%S')} kicked {len(urls)} web seeds: {t['name']} ({t['progress']*100:.2f}%)")
