#!/usr/bin/env python3
"""archive.org helper for the download portal (downloads.kebin.dev/ia/). Runs as media-ia-queue.service on :8097.

Paste an archive.org item link or identifier; every "original" file of the item is queued into aria2 (RPC on
127.0.0.1:6800) with its MD5 from the item's manifest, so aria2 verifies each file after download. Files land
in /downloads/<item>/... which is /mnt/storage/Media/Downloads/<item>/ on the host. ?dry=1 only lists them."""
import html, json, re, urllib.parse, urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT, RPC = 8097, "http://127.0.0.1:6800/jsonrpc"
SECRET = re.search(r'^ARIA2_RPC_SECRET=(.*)$', open("/srv/media/.env").read(), re.M).group(1).strip().strip('"\'')
UA = {"User-Agent": "kebin.dev ia-queue (python-urllib)"}


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


def manifest(item):
    meta = json.load(urllib.request.urlopen(urllib.request.Request(f"https://archive.org/metadata/{urllib.parse.quote(item)}", headers=UA), timeout=120))
    if not meta.get("files"):
        raise RuntimeError("no such item, or it has no files")
    return [f for f in meta["files"] if f.get("source") == "original"]


def queue(item, files):
    gids = []
    for f in files:
        name = f["name"]
        sub, base = (name.rsplit("/", 1) if "/" in name else ("", name))
        opts = {"dir": f"/downloads/{item}" + (f"/{sub}" if sub else ""), "out": base}
        if f.get("md5"):
            opts["checksum"] = f"md5={f['md5']}"
        gids.append(rpc("aria2.addUri", [f"https://archive.org/download/{urllib.parse.quote(item)}/{urllib.parse.quote(name)}"], opts))
    return gids


def page(msg="", rows=""):
    return f"""<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>archive.org · downloads</title>
<style>body{{font:15px/1.5 system-ui,sans-serif;background:#111;color:#eee;margin:auto;padding:24px;max-width:860px}}input[type=text]{{width:100%;padding:10px;font-size:15px;background:#1c1c1c;color:#eee;border:1px solid #333;border-radius:6px}}
button{{padding:10px 16px;margin:10px 8px 0 0;font-size:15px;border:0;border-radius:6px;background:#ffd23f;color:#111;cursor:pointer}}button.alt{{background:#333;color:#eee}}p.msg{{color:#ffd23f}}table{{border-collapse:collapse;width:100%;font-size:13px}}td,th{{text-align:left;padding:3px 8px 3px 0;border-bottom:1px solid #222;color:#aaa}}a{{color:#ffd23f}}</style></head><body>
<h1>Queue an archive.org item</h1><p>Paste an archive.org link (details, download or metadata page) or just the identifier. Every original file of the item goes to aria2 with its MD5, into <code>Downloads/&lt;item&gt;/</code>. Watch and control it in the <a href="/">portal</a>.</p>
<form method="post"><input type="text" name="item" placeholder="https://archive.org/details/some-item" required><button type="submit">Queue all files</button><button class="alt" type="submit" name="dry" value="1">Preview only</button></form>
{f'<p class="msg">{msg}</p>' if msg else ''}{rows}</body></html>"""


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


ThreadingHTTPServer(("0.0.0.0", PORT), H).serve_forever()
