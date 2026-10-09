#!/usr/bin/env python3
"""Pull whole archive.org items over plain HTTP, fast, with verification. Runs as media-ia-fetch.service.

- Items: one archive.org identifier per line in /srv/media/ia-fetch.items (# comments allowed). The file is
  re-read every pass, so appending an identifier queues it.
- Each item's "original" files land in /mnt/storage/Media/Downloads/<item>/..., downloaded as 24 parallel
  byte-range requests into <file>.part, then MD5-checked against the item's manifest and renamed into place.
  Verified files are remembered in .ia-fetch-state.json inside the Downloads folder and never re-fetched.
- Status: http://<media VM>:8097/ (HTML, refreshes itself), /status.json, /health. Exposed as downloads.kebin.dev.
Why not the torrents: archive.org's data nodes drop ~2% of requests with HTTP 500; libtorrent reacts by giving
up on the seed and waiting, which averaged 1-10 MB/s on a line that does 110 MB/s. Plain ranges just retry."""
import hashlib, html, json, os, queue, threading, time, urllib.error, urllib.parse, urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ITEMS_FILE = "/srv/media/ia-fetch.items"
ROOT = "/mnt/storage/Media/Downloads"
STATE_FILE = os.path.join(ROOT, ".ia-fetch-state.json")
WORKERS, CHUNK, PORT, OWNER = 24, 32 << 20, 8097, (1000, 1000)
UA = {"User-Agent": "kebin.dev ia-fetch (python-urllib)"}


def log(*a):
    print(time.strftime("%Y-%m-%dT%H:%M:%S"), *a, flush=True)


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *a, **k):
        return None


no_redirect = urllib.request.build_opener(NoRedirect)


def resolve(item, name):
    """archive.org/download redirects every file to a data node; follow it once per file."""
    url = f"https://archive.org/download/{urllib.parse.quote(item)}/{urllib.parse.quote(name)}"
    for attempt in range(20):
        try:
            no_redirect.open(urllib.request.Request(url, headers=UA), timeout=60).close()
            return url
        except urllib.error.HTTPError as e:
            if e.code in (301, 302, 307, 308):
                return e.headers["Location"]
            log(f"resolve {name}: HTTP {e.code}, retrying")
        except Exception as e:
            log(f"resolve {name}: {e}, retrying")
        time.sleep(min(5 * (attempt + 1), 60))
    raise RuntimeError(f"cannot resolve {name}")


# ---- status shared with the web thread ----
S = {"started": time.time(), "items": {}, "current": None, "speed": 0.0, "idle": False, "pass": 0}
lock = threading.Lock()
window = []  # (t, bytes) for the speed average


def note_bytes(n):
    now = time.time()
    with lock:
        window.append((now, n))
        while window and window[0][0] < now - 15:
            window.pop(0)
        span = now - window[0][0] if window else 1
        S["speed"] = sum(b for _, b in window) / max(span, 1)


def load_state():
    try:
        return json.load(open(STATE_FILE))
    except Exception:
        return {}


def save_state(st):
    tmp = STATE_FILE + ".tmp"
    json.dump(st, open(tmp, "w"), indent=1)
    os.replace(tmp, STATE_FILE)
    os.chown(STATE_FILE, *OWNER)


def md5_of(path):
    h = hashlib.md5()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(8 << 20), b""):
            h.update(block)
    return h.hexdigest()


def fetch_file(item, f, dest):
    """Download one file as parallel ranges into dest+'.part'. Returns True when the MD5 matches."""
    name, size, want = f["name"], f["size"], f.get("md5")
    part = dest + ".part"
    os.makedirs(os.path.dirname(part), exist_ok=True)
    with open(part, "wb") as fh:
        fh.truncate(size)
    fd = os.open(part, os.O_WRONLY)
    url = [resolve(item, name)]
    q = queue.Queue()
    for start in range(0, size, CHUNK):
        q.put((start, min(start + CHUNK, size) - 1))
    done = [0]
    errors = []
    fs = S["items"][item]["files"][name]

    def worker():
        while not errors:
            try:
                start, end = q.get_nowait()
            except queue.Empty:
                return
            for attempt in range(40):
                pos = start
                try:
                    r = urllib.request.urlopen(urllib.request.Request(url[0], headers={**UA, "Range": f"bytes={start}-{end}"}), timeout=180)
                    if r.status != 206:
                        raise RuntimeError(f"HTTP {r.status} without range support")
                    while pos <= end:
                        block = r.read(min(1 << 20, end - pos + 1))
                        if not block:
                            raise RuntimeError("short read")
                        os.pwrite(fd, block, pos)
                        pos += len(block)
                        note_bytes(len(block))
                        with lock:
                            done[0] += len(block)
                            fs["done"] = done[0]
                    r.close()
                    break
                except Exception as e:
                    with lock:
                        done[0] -= pos - start
                        fs["done"] = max(done[0], 0)
                        fs["retries"] = fs.get("retries", 0) + 1
                    if isinstance(e, urllib.error.HTTPError) and e.code in (403, 404):
                        try:
                            url[0] = resolve(item, name)
                        except Exception:
                            pass
                    time.sleep(min(2 * attempt + 1, 30))
            else:
                errors.append(f"{name} {start}-{end}: gave up")
                return

    th = [threading.Thread(target=worker, daemon=True) for _ in range(min(WORKERS, max(1, (size + CHUNK - 1) // CHUNK)))]
    for t in th:
        t.start()
    for t in th:
        t.join()
    os.fsync(fd)
    os.close(fd)
    if errors:
        log("ERROR", errors[0])
        return False
    if size == 0 or not want:
        log(f"  {name}: no checksum published, kept unverified")
    else:
        fs["state"] = "verifying"
        got = md5_of(part)
        if got != want:
            log(f"  {name}: MD5 MISMATCH {got} != {want}, will retry")
            os.remove(part)
            return False
    os.replace(part, dest)
    os.chown(dest, *OWNER)
    return True


def read_items():
    try:
        return [l.strip() for l in open(ITEMS_FILE) if l.strip() and not l.startswith("#")]
    except FileNotFoundError:
        return []


def item_files(item):
    meta = json.load(urllib.request.urlopen(urllib.request.Request(f"https://archive.org/metadata/{urllib.parse.quote(item)}", headers=UA), timeout=120))
    if not meta.get("files"):
        raise RuntimeError("no such item or no files")
    return [{"name": f["name"], "size": int(f.get("size", 0) or 0), "md5": f.get("md5")} for f in meta["files"] if f.get("source") == "original"]


def run_pass():
    state = load_state()
    S["pass"] += 1
    manifests = {}
    for item in read_items():          # all manifests first, so the totals and the ETA are right from the start
        try:
            manifests[item] = item_files(item)
            entry = S["items"].setdefault(item, {"files": {}, "size": 0})
            entry["size"] = sum(f["size"] for f in manifests[item])
            for f in manifests[item]:
                entry["files"].setdefault(f["name"], {"size": f["size"], "done": 0, "state": "pending"})
        except Exception as e:
            log(f"{item}: metadata failed: {e}")
            S["items"][item] = {"error": str(e), "files": {}, "size": 0}
    for item, files in manifests.items():
        st = state.setdefault(item, {})
        entry = S["items"].setdefault(item, {"files": {}, "size": 0})
        entry["size"] = sum(f["size"] for f in files)
        entry["error"] = None
        for f in files:
            dest = os.path.join(ROOT, item, f["name"])
            known = st.get(f["name"])
            if known and known.get("md5") == f["md5"] and os.path.isfile(dest) and os.path.getsize(dest) == f["size"]:
                entry["files"][f["name"]] = {"size": f["size"], "done": f["size"], "state": "verified"}
                continue
            if os.path.isfile(dest) and os.path.getsize(dest) == f["size"] and f["md5"]:
                entry["files"][f["name"]] = {"size": f["size"], "done": f["size"], "state": "verifying"}
                if md5_of(dest) == f["md5"]:
                    st[f["name"]] = {"md5": f["md5"], "verified": time.time()}
                    save_state(state)
                    entry["files"][f["name"]]["state"] = "verified"
                    log(f"{item}/{f['name']}: already present, MD5 ok")
                    continue
                log(f"{item}/{f['name']}: present but MD5 differs, re-downloading")
            entry["files"][f["name"]] = {"size": f["size"], "done": 0, "state": "pending"}
        for f in files:
            fs = entry["files"][f["name"]]
            if fs["state"] == "verified":
                continue
            S["current"] = (item, f["name"])
            fs["state"] = "downloading"
            fs["done"] = 0
            t0 = time.time()
            ok = False
            for attempt in range(3):
                try:
                    ok = fetch_file(item, f, os.path.join(ROOT, item, f["name"]))
                except Exception as e:
                    log(f"  {f['name']}: {e}")
                if ok:
                    break
                fs["done"] = 0
            if ok:
                fs["state"] = "verified"
                fs["done"] = f["size"]
                st[f["name"]] = {"md5": f["md5"], "verified": time.time()}
                save_state(state)
                log(f"{item}/{f['name']}: {f['size']/2**30:.2f} GB in {(time.time()-t0)/60:.1f} min, MD5 ok")
            else:
                fs["state"] = "failed"
                log(f"{item}/{f['name']}: FAILED after 3 attempts")
            S["current"] = None
    for d in (os.path.join(ROOT, i) for i in read_items()):
        if os.path.isdir(d):
            os.chown(d, *OWNER)


# ---- status page ----
def snapshot():
    with lock:
        items = []
        for name, it in S["items"].items():
            fl = it["files"]
            done = sum(f["done"] for f in fl.values())
            items.append({"item": name, "size": it["size"], "done": done, "error": it.get("error"),
                          "files": [{"name": n, **f} for n, f in fl.items()]})
        total = sum(i["size"] for i in items)
        tdone = sum(i["done"] for i in items)
        eta = (total - tdone) / S["speed"] if S["speed"] > 1e5 else None
        return {"items": items, "total": total, "done": tdone, "speed": S["speed"], "eta_s": eta,
                "current": S["current"], "idle": S["idle"], "pass": S["pass"], "uptime_s": time.time() - S["started"]}


def gb(n):
    return f"{n/2**30:,.1f} GB"


def page(s):
    def hms(x):
        return "-" if x is None else f"{int(x//3600)}h {int(x%3600//60):02d}m"
    rows = []
    for it in s["items"]:
        pct = 100 * it["done"] / it["size"] if it["size"] else 0
        files = ""
        for f in it["files"]:
            if f["state"] == "verified":
                continue
            extra = f" {int(100*f['done']/f['size'])}%" if f["state"] == "downloading" and f["size"] else ""
            files += f'<tr class="{f["state"]}"><td>{html.escape(f["name"])}</td><td>{gb(f["size"])}</td><td>{f["state"]}{extra}</td></tr>'
        nver = sum(f["state"] == "verified" for f in it["files"])
        err = f' · <b>{html.escape(it["error"])}</b>' if it["error"] else ""
        table = f"<table><tr><th>remaining file</th><th>size</th><th>state</th></tr>{files}</table>" if files else ""
        rows.append(f'<section><h2>{html.escape(it["item"])}</h2><div class="bar"><div style="width:{pct:.1f}%"></div></div>'
                    f'<p>{gb(it["done"])} of {gb(it["size"])} · {pct:.1f}% · {nver}/{len(it["files"])} files verified{err}</p>{table}</section>')
    pct = 100 * s["done"] / s["total"] if s["total"] else 0
    now = "now: " + html.escape("/".join(s["current"])) if s["current"] else ("idle, everything verified" if s["idle"] else "starting")
    return f"""<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="refresh" content="10">
<title>Downloads · kebin</title><style>body{{font:15px/1.5 system-ui,sans-serif;background:#111;color:#eee;margin:auto;padding:24px;max-width:960px}}h1{{font-size:22px}}h2{{font-size:17px;margin:28px 0 6px;word-break:break-all}}
.bar{{background:#2a2a2a;border-radius:6px;height:12px;overflow:hidden}}.bar div{{background:#ffd23f;height:100%}}p{{margin:6px 0 10px;color:#bbb}}b{{color:#ff6b6b}}table{{border-collapse:collapse;width:100%;font-size:13px}}td,th{{text-align:left;padding:3px 8px 3px 0;border-bottom:1px solid #222;color:#999}}
tr.downloading td{{color:#ffd23f}}tr.failed td{{color:#ff6b6b}}tr.verifying td{{color:#8be9fd}}.big{{font-size:28px;font-weight:600;color:#fff}}</style></head><body>
<h1>archive.org downloads</h1><div class="big">{gb(s["done"])} / {gb(s["total"])} · {pct:.1f}%</div>
<p>{s["speed"]/2**20:.1f} MB/s · ETA {hms(s["eta_s"])} · {now}</p>
<div class="bar"><div style="width:{pct:.1f}%"></div></div>{"".join(rows)}
<p style="margin-top:32px;font-size:12px">Files are pulled as 24 parallel ranges and MD5-checked against archive.org's manifest. Queue: /srv/media/ia-fetch.items on the media VM. Page refreshes every 10 s.</p></body></html>"""


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        if self.path.startswith("/status.json"):
            body, ct = json.dumps(snapshot()).encode(), "application/json"
        elif self.path.startswith("/health"):
            body, ct = b"ok", "text/plain"
        else:
            body, ct = page(snapshot()).encode(), "text/html; charset=utf-8"
        self.send_response(200)
        self.send_header("Content-Type", ct)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


threading.Thread(target=ThreadingHTTPServer(("0.0.0.0", PORT), H).serve_forever, daemon=True).start()
log(f"ia-fetch started, status on :{PORT}, {WORKERS} workers, {CHUNK>>20} MB ranges")
while True:
    S["idle"] = False
    try:
        run_pass()
    except Exception as e:
        log("pass failed:", e)
    S["idle"] = True
    time.sleep(600)
