#!/usr/bin/env python3
"""Remove titles you already own from the JellyBridge Discover library.

Jellyfin 10.11+/12 no longer honors .ignore files, so JellyBridge's own
"hide existing content" leaves bare folder tiles. This runs after the plugin's
daily sync and removes any Discover entry whose TMDB id (or name+year) matches
a title in the Movies or TV libraries. Folders are renamed aside before the
Jellyfin delete so Jellyfin never touches the real files, then removed.
"""
import json, re, os, shutil, sys, time, urllib.request

ENV = "/srv/media/.env"
JB_HOST = "/srv/media/jellybridge"
JB_CONTAINER = "/jellybridge"
B = "http://127.0.0.1:8096"
A = 'MediaBrowser Client="jellybridge-prune", Device="media-vm", DeviceId="jb-prune-1", Version="1.0"'
ENV_TEXT = open(ENV).read()
pw = re.search(r"JF_ADMIN_PASSWORD=(\S+)", ENV_TEXT).group(1)
m = re.search(r"JF_ADMIN_USER=(\S+)", ENV_TEXT)
USERNAME = m.group(1) if m else "admin"
tok = None

def call(path, body=None, method=None):
    d = None if body is None else json.dumps(body).encode()
    r = urllib.request.Request(B + path, data=d, method=method or ("POST" if d is not None else "GET"),
                               headers={"Content-Type": "application/json", "Authorization": A + (f', Token="{tok}"' if tok else "")})
    try:
        with urllib.request.urlopen(r, timeout=120) as x:
            t = x.read(); return (json.loads(t) if t else None), x.status
    except urllib.error.HTTPError as e:
        return e.read().decode()[:200], e.code

for _ in range(30):
    try: urllib.request.urlopen(B + "/health", timeout=5); break
    except Exception: time.sleep(10)
tok = call("/Users/AuthenticateByName", {"Username": USERNAME, "Pw": pw})[0]["AccessToken"]
libs = {v["Name"]: v["ItemId"] for v in call("/Library/VirtualFolders")[0]}
if "Discover" not in libs: print("no Discover library"); sys.exit(0)

def key(i):
    k = set()
    t = (i.get("ProviderIds") or {}).get("Tmdb")
    if t: k.add(("tmdb", i["Type"], str(t)))
    if i.get("ProductionYear"): k.add(("name", i["Type"], i["Name"].strip().lower(), i["ProductionYear"]))
    return k

owned = set()
for lib in ("Movies", "TV"):
    if lib not in libs: continue
    for i in call(f"/Items?ParentId={libs[lib]}&Recursive=true&IncludeItemTypes=Movie,Series&Fields=ProviderIds,ProductionYear&Limit=10000")[0]["Items"]:
        owned |= key(i)

removed = 0
for i in call(f"/Items?ParentId={libs['Discover']}&Fields=ProviderIds,ProductionYear,Path&Limit=10000")[0]["Items"]:
    ks = key(i)
    m = re.search(r"\[tmdbid-(\d+)\]", os.path.basename(i.get("Path") or ""))
    if m: ks.add(("tmdb", i["Type"] if i["Type"] in ("Movie", "Series") else "Movie", m.group(1)))
    if i["Type"] == "Folder" and m: ks |= {("tmdb", "Movie", m.group(1)), ("tmdb", "Series", m.group(1))}
    if not (ks & owned): continue
    p = (i.get("Path") or "").replace(JB_CONTAINER, JB_HOST, 1)
    aside = None
    if p.startswith(JB_HOST + "/") and os.path.isdir(p):
        aside = p + ".prune"; os.rename(p, aside)
    r, s = call(f"/Items/{i['Id']}", method="DELETE")
    if aside: shutil.rmtree(aside, ignore_errors=True)
    print(f"removed from Discover: {i['Name']} ({i['Type']}) -> {s}")
    removed += 1
print(f"done: {removed} owned title(s) removed from Discover")
