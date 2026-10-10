#!/usr/bin/env python3
"""archive.org helper for the download portal (downloads.kebin.dev/ia/). Runs as media-ia-queue.service on :8097.

Paste an archive.org item link or identifier; every "original" file of the item is queued into aria2 (RPC on
127.0.0.1:6800). A verifier thread MD5-checks each finished file against the item's manifest (one at a time,
state in /srv/media/ia-verify.json) and re-queues a mismatch. Files land
in /downloads/<item>/... which is /mnt/storage/Media/Downloads/<item>/ on the host. ?dry=1 only lists them."""
import hashlib, html, json, os, re, threading, time, urllib.parse, urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT, RPC = 8097, "http://127.0.0.1:6800/jsonrpc"
SECRET = re.search(r'^ARIA2_RPC_SECRET=(.*)$', open("/srv/media/.env").read(), re.M).group(1).strip().strip('"\'')
UA = {"User-Agent": "kebin.dev ia-queue (python-urllib)"}
SIZES = {}   # item -> {file name: size} from the manifest, for tasks aria2 has not started yet


def rpc(method, *params):
    body = json.dumps({"jsonrpc": "2.0", "id": "q", "method": method, "params": [f"token:{SECRET}", *params]}).encode()
    r = json.load(urllib.request.urlopen(urllib.request.Request(RPC, data=body, headers={"Content-Type": "application/json"}), timeout=60))
    if "error" in r:
        raise RuntimeError(r["error"].get("message", r["error"]))
    return r["result"]


def identifier(text):
    text = text.strip()
    m = re.search(r"archive\.org/(?:details|download|metadata)/([^/?#\s]+)", text)
    return m.group(1) if m else re.sub(r"[^A-Za-z0-9._-]", "", text)


IA_OWN = re.compile(r"_(files\.xml|meta\.xml|meta\.sqlite|reviews\.xml|archive\.torrent)$")   # archive.org's own bookkeeping


def manifest(item):
    meta = json.load(urllib.request.urlopen(urllib.request.Request(f"https://archive.org/metadata/{urllib.parse.quote(item)}", headers=UA), timeout=120))
    if not meta.get("files"):
        raise RuntimeError("no such item, or it has no files")
    # archive.org rewrites its own index files whenever the item is touched, so their manifest MD5 never matches
    # what is served (seen 2026-10-09: _files.xml failed with checksum error 32). They are not the upload; skip them.
    return [f for f in meta["files"] if f.get("source") == "original" and not IA_OWN.search(f["name"])]


def add_task(item, name):
    sub, base = (name.rsplit("/", 1) if "/" in name else ("", name))
    opts = {"dir": f"/downloads/{item}" + (f"/{sub}" if sub else ""), "out": base}
    return rpc("aria2.addUri", [f"https://archive.org/download/{urllib.parse.quote(item)}/{urllib.parse.quote(name)}"], opts)


def queue(item, files):
    """Queue every file. No checksum option: aria2 verifies one file at a time at ~90 MB/s and finished files then
    sit in download slots waiting their turn, which starved the downloads (2026-10-09). The verifier thread below
    hashes finished files in parallel instead."""
    with VLOCK:
        st = vstate()
        if item not in st["items"]:
            st["items"].append(item)
        vsave(st)
    return [add_task(item, f["name"]) for f in files]


# ---- verification: every finished file is MD5-checked against the manifest, in parallel, outside aria2 ----
VERIFY_STATE = "/srv/media/ia-verify.json"
HOST_ROOT = "/mnt/storage/Media/Downloads"
VLOCK = threading.Lock()
MD5S = {}          # item -> {file name: md5}


def vstate():
    try:
        return json.load(open(VERIFY_STATE))
    except Exception:
        return {"items": [], "files": {}}


def vsave(st):
    tmp = VERIFY_STATE + ".tmp"
    json.dump(st, open(tmp, "w"), indent=1)
    os.replace(tmp, VERIFY_STATE)


def md5_file(path):
    h = hashlib.md5()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(8 << 20), b""):
            h.update(block)
    return h.hexdigest()


def verify_one(item, name, want):
    path = os.path.join(HOST_ROOT, item, name)
    key = f"{item}/{name}"
    got = md5_file(path) if want else None
    with VLOCK:
        st = vstate()
        rec = st["files"].get(key, {"attempts": 0})
        if not want or got == want:
            rec.update({"ok": True, "md5": got, "at": time.time(), "note": None if want else "no checksum published"})
            print(time.strftime("%H:%M:%S"), "ok  ", key, flush=True)
        else:
            rec["attempts"] += 1
            rec.update({"ok": False, "md5": got, "at": time.time()})
            print(time.strftime("%H:%M:%S"), f"BAD {key}: {got} != {want}, attempt {rec['attempts']}", flush=True)
            if rec["attempts"] <= 2:
                try:
                    os.remove(path)
                    add_task(item, name)
                    rec["note"] = "re-queued"
                except Exception as e:
                    rec["note"] = f"re-queue failed: {e}"
            else:
                rec["note"] = "failed twice, left for a human"
        st["files"][key] = rec
        vsave(st)


def verify_loop():
    import concurrent.futures as cf
    pool = cf.ThreadPoolExecutor(1)      # one at a time: three parallel readers stalled aria2's event loop on the NAS
    busy = set()
    while True:
        try:
            st = vstate()
            for item in list(st["items"]):
                if item not in MD5S:
                    try:
                        MD5S[item] = {f["name"]: (f.get("md5"), int(f.get("size", 0) or 0)) for f in manifest(item)}
                    except Exception as e:
                        print("manifest failed for", item, e, flush=True)
                        continue
                for name, (want, size) in MD5S[item].items():
                    key = f"{item}/{name}"
                    rec = st["files"].get(key)
                    if (rec and rec.get("ok")) or key in busy:
                        continue
                    if rec and not rec.get("ok") and rec.get("attempts", 0) > 2:
                        continue
                    path = os.path.join(HOST_ROOT, item, name)
                    if not os.path.isfile(path) or os.path.exists(path + ".aria2") or os.path.getsize(path) != size:
                        continue          # not finished yet (or size wrong: aria2 will finish/re-get it)
                    busy.add(key)
                    pool.submit(lambda i=item, n=name, w=want, k=key: (verify_one(i, n, w), busy.discard(k)))
        except Exception as e:
            print("verify loop:", e, flush=True)
        time.sleep(20)


def verify_summary(item):
    """(verified, total files in manifest, failed names, pending count) for the status table."""
    st = vstate()
    names = MD5S.get(item, {})
    ok = sum(1 for n in names if st["files"].get(f"{item}/{n}", {}).get("ok"))
    bad = [n for n in names if st["files"].get(f"{item}/{n}") and not st["files"][f"{item}/{n}"].get("ok") and st["files"][f"{item}/{n}"].get("attempts", 0) > 2]
    return ok, len(names), bad


def overview():
    """One row per queued archive.org link: everything aria2 knows about, grouped by the item folder."""
    tasks = rpc("aria2.tellActive") + rpc("aria2.tellWaiting", 0, 10000) + rpc("aria2.tellStopped", 0, 10000)
    items = {}
    for t in tasks:
        d = t.get("dir", "")
        if not d.startswith("/downloads/") or not t.get("files"):
            continue
        item = d[len("/downloads/"):].split("/", 1)[0]
        it = items.setdefault(item, {"files": 0, "done": 0, "total": 0, "complete": 0, "speed": 0, "errors": 0, "active": 0})
        total, comp = int(t.get("totalLength", 0)), int(t.get("completedLength", 0))
        if total == 0:                      # a queued task has no size yet; take it from the item's manifest
            if item not in SIZES:
                try:
                    SIZES[item] = {f["name"]: int(f.get("size", 0) or 0) for f in manifest(item)}
                except Exception:
                    SIZES[item] = {}
            rel = t["files"][0].get("path", "")[len(f"/downloads/{item}/"):]
            total = SIZES[item].get(rel, 0)
        it["files"] += 1
        it["total"] += total
        it["done"] += comp
        it["speed"] += int(t.get("downloadSpeed", 0))
        it["complete"] += t["status"] == "complete"
        it["errors"] += t["status"] == "error"
        it["active"] += t["status"] == "active"
    if not items:
        return ""
    rows = ""
    for item, it in sorted(items.items()):
        pct = 100 * it["done"] / it["total"] if it["total"] else 0
        left = it["total"] - it["done"]
        state = "done" if it["complete"] == it["files"] else ("downloading" if it["active"] else "queued")
        eta = "done" if state == "done" else (f"{left / it['speed'] / 3600:.1f} h" if it["speed"] > 1e5 else "-")
        err = f' · <b>{it["errors"]} failed</b>' if it["errors"] else ""
        vok, vtotal, vbad = verify_summary(item)
        ver = f"{vok}/{vtotal}" + (f' <b>{len(vbad)} bad: {html.escape(", ".join(vbad)[:80])}</b>' if vbad else "")
        rows += (f'<tr><td><a href="https://archive.org/details/{html.escape(item)}" target="_blank">{html.escape(item)}</a></td>'
                 f'<td>{it["complete"]}/{it["files"]}</td><td>{ver}</td><td>{it["done"]/2**30:,.1f} / {it["total"]/2**30:,.1f} GB</td>'
                 f'<td><div class="bar"><div style="width:{pct:.1f}%"></div></div>{pct:.1f}%</td>'
                 f'<td>{it["speed"]/2**20:.1f} MB/s</td><td>{eta}</td><td>{state}{err}</td></tr>')
    return f'<h2>Queued links</h2><table><tr><th>item</th><th>downloaded</th><th>verified</th><th>size</th><th>progress</th><th>speed</th><th>ETA</th><th>state</th></tr>{rows}</table><p class="small">Refreshes every 10 s. "verified" = finished files whose MD5 matched archive.org\'s manifest; a mismatch is deleted and re-queued, twice at most, then shown in red. Totals cover what aria2 still lists; clearing finished tasks in the portal drops them from here.</p>'


def page(msg="", rows=""):
    try:
        status = overview()
    except Exception as e:
        status = f'<p class="msg">portal not reachable: {html.escape(str(e))}</p>'
    return f"""<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="refresh" content="10"><title>archive.org · downloads</title>
<style>body{{font:15px/1.5 system-ui,sans-serif;background:#111;color:#eee;margin:auto;padding:24px;max-width:860px}}input[type=text]{{width:100%;padding:10px;font-size:15px;background:#1c1c1c;color:#eee;border:1px solid #333;border-radius:6px}}
button{{padding:10px 16px;margin:10px 8px 0 0;font-size:15px;border:0;border-radius:6px;background:#ffd23f;color:#111;cursor:pointer}}button.alt{{background:#333;color:#eee}}p.msg{{color:#ffd23f}}table{{border-collapse:collapse;width:100%;font-size:13px}}td,th{{text-align:left;padding:5px 10px 5px 0;border-bottom:1px solid #222;color:#aaa;vertical-align:middle}}a{{color:#ffd23f}}
h2{{font-size:17px;margin:32px 0 8px}}.bar{{background:#2a2a2a;border-radius:4px;height:8px;overflow:hidden;min-width:120px;margin-bottom:3px}}.bar div{{background:#ffd23f;height:100%}}b{{color:#ff6b6b}}p.small{{font-size:12px;color:#777}}</style></head><body>
<h1>Queue an archive.org item</h1><p>Paste an archive.org link (details, download or metadata page) or just the identifier. Every original file of the item goes to aria2 and is MD5-checked against the manifest when it finishes, into <code>Downloads/&lt;item&gt;/</code>. Watch and control it in the <a href="/">portal</a>.</p>
<form method="post"><input type="text" name="item" placeholder="https://archive.org/details/some-item" required><button type="submit">Queue all files</button><button class="alt" type="submit" name="dry" value="1">Preview only</button></form>
{f'<p class="msg">{msg}</p>' if msg else ''}{rows}{status}</body></html>"""


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def send(self, body, code=200, ct="text/html; charset=utf-8"):
        body = body.encode() if isinstance(body, str) else body
        self.send_response(code)
        self.send_header("Content-Type", ct)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path.startswith("/ia/health") or self.path.startswith("/health"):
            return self.send(b"ok", ct="text/plain")
        self.send(page())

    def do_POST(self):
        form = urllib.parse.parse_qs(self.rfile.read(int(self.headers.get("Content-Length", 0))).decode())
        item = identifier(form.get("item", [""])[0])
        dry = bool(form.get("dry"))
        if not item:
            return self.send(page("Give me a link or an identifier."))
        try:
            files = manifest(item)
            rows = "<table><tr><th>file</th><th>size</th><th>md5</th></tr>" + "".join(
                f"<tr><td>{html.escape(f['name'])}</td><td>{int(f.get('size', 0) or 0)/2**30:.2f} GB</td><td>{'yes' if f.get('md5') else 'no'}</td></tr>" for f in files) + "</table>"
            total = sum(int(f.get("size", 0) or 0) for f in files) / 2**30
            if dry:
                return self.send(page(f"{html.escape(item)}: {len(files)} files, {total:.1f} GB. Nothing queued.", rows))
            gids = queue(item, files)
            self.send(page(f"{html.escape(item)}: queued {len(gids)} files, {total:.1f} GB. <a href='/'>Open the portal</a> to watch them.", rows))
        except Exception as e:
            self.send(page(f"Failed: {html.escape(str(e))}"))


threading.Thread(target=verify_loop, daemon=True).start()
ThreadingHTTPServer(("0.0.0.0", PORT), H).serve_forever()
