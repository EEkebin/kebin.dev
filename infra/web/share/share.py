#!/usr/bin/env python3
"""share.kebin.dev: send files between browsers, LocalSend-style. Runs on the web VM as kebin-share.service, 127.0.0.1:8766.

- Every browser joins with a random name and its own 4-digit PIN (kept across visits: the browser stores an id+token,
  the server stores the id, name, PIN and a hash of the token in $STATE_DIRECTORY/clients.json).
- Browsers on the same network (same public IPv4, or same IPv6 /64) see each other automatically. Anyone else is
  reached by typing their PIN.
- Sending = an offer (file names and sizes) that the receiver must accept. Files then go browser to browser over
  WebRTC; this server only passes the connection messages. If no direct connection can be made, or a file is too big
  to hold in the receiver's browser memory, the file is streamed through this server (relay): nothing is written to
  disk, the relay only exists for an offer the receiver accepted, and only the two parties can use it.
No login on purpose: the files go between the people using it, never to the homelab.
"""
import hashlib, ipaddress, json, os, queue, re, secrets, threading, time, urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = 8766
HERE = os.path.dirname(os.path.abspath(__file__))
STATE = os.path.join(os.environ.get("STATE_DIRECTORY", "/var/lib/kebin-share"), "clients.json")
KEEP_DAYS = 90                 # forget a browser (and free its PIN) after this long unseen
MAX_RELAYS = 6                 # concurrent relayed files
CHUNK = 256 << 10

ADJ = ("Amber Brave Bright Calm Clever Cosmic Crimson Curious Dapper Eager Electric Fancy Fluffy Gentle Golden Happy "
       "Jolly Lucky Lunar Mellow Mighty Misty Nimble Noble Polar Quick Quiet Rapid Rusty Shiny Silent Silver Sleepy "
       "Snowy Solar Sunny Swift Tidy Velvet Witty Zesty").split()
NOUN = ("Badger Bear Beaver Bison Cat Cobra Crane Deer Dolphin Eagle Falcon Ferret Fox Gecko Heron Koala Lemur Lion "
        "Llama Lynx Moose Otter Owl Panda Parrot Penguin Puffin Rabbit Raccoon Raven Seal Shark Sloth Swan Tiger "
        "Toucan Turtle Walrus Whale Wolf").split()

lock = threading.RLock()
clients = {}     # id -> {"name", "pin", "tok": sha256 hex, "last": epoch}
online = {}      # id -> list of Session
offers = {}      # tid -> {"frm", "to", "files": [{name,size,type}], "accepted": bool, "at": epoch}
relays = {}      # "tid/i" -> Relay
hits = {}        # (who, kind) -> [epochs]  for rate limits


def h(tok):
    return hashlib.sha256(tok.encode()).hexdigest()


def load():
    global clients
    try:
        clients = json.load(open(STATE))
    except Exception:
        clients = {}
    cutoff = time.time() - KEEP_DAYS * 86400
    clients = {k: v for k, v in clients.items() if v.get("last", 0) > cutoff}


def save():
    tmp = STATE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(clients, f)
    os.replace(tmp, STATE)


def allow(who, kind, n, per):
    now = time.time()
    with lock:
        ts = [t for t in hits.get((who, kind), []) if t > now - per]
        if len(ts) >= n:
            hits[(who, kind)] = ts
            return False
        ts.append(now)
        hits[(who, kind)] = ts
        return True


def new_pin():
    used = {c["pin"] for c in clients.values()}
    for _ in range(200):
        p = f"{secrets.randbelow(10000):04d}"
        if p not in used:
            return p
    raise RuntimeError("no free PIN")


def net_of(ip):
    try:
        a = ipaddress.ip_address(ip)
        if a.version == 6 and a.ipv4_mapped:
            return str(a.ipv4_mapped)
        if a.version == 6:
            return str(ipaddress.ip_network(f"{a}/64", strict=False))
        return str(a)
    except ValueError:
        return ip


def public(cid):
    c = clients[cid]
    return {"id": cid, "name": c["name"], "pin": c["pin"]}


class Session:
    def __init__(self, cid, net):
        self.cid, self.net, self.q = cid, net, queue.Queue()


def push(cid, ev):
    for s in online.get(cid, []):
        s.q.put(ev)


def broadcast_peers(net):
    with lock:
        here = {s.cid for ss in online.values() for s in ss if s.net == net}
        for cid in here:
            peers = [public(o) for o in sorted(here) if o != cid]
            push(cid, {"type": "peers", "peers": peers})


def find(to):
    """to = a client id or a 4-digit PIN; returns the id of an online client or None."""
    to = str(to or "").strip()
    with lock:
        if re.fullmatch(r"\d{4}", to):
            for cid, c in clients.items():
                if c["pin"] == to and online.get(cid):
                    return cid
            return None
        return to if online.get(to) else None


class Relay:
    def __init__(self, size):
        self.q = queue.Queue(maxsize=64)     # 64 x 256 KB = 16 MB in flight at most
        self.size = size
        self.taken = False
        self.failed = False
        self.done = threading.Event()
        self.started = time.time()


class H(BaseHTTPRequestHandler):
    server_version = "kebin-share"

    def log_message(self, *a):
        pass

    # ---- helpers ----
    def ip(self):
        return self.headers.get("X-Real-IP") or self.client_address[0]

    def reply(self, code, obj=None, body=None, ctype="application/json"):
        data = body if body is not None else json.dumps(obj or {}).encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def body_json(self):
        n = int(self.headers.get("Content-Length") or 0)
        if n > 65536:
            raise ValueError("too big")
        return json.loads(self.rfile.read(n) or b"{}")

    def auth(self, cid, tok):
        with lock:
            c = clients.get(cid or "")
            if not c or not tok or c["tok"] != h(tok):
                return None
            c["last"] = time.time()
            return cid

    # ---- routes ----
    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        qs = dict(urllib.parse.parse_qsl(u.query))
        if u.path == "/api/health":
            return self.reply(200, body=b"ok", ctype="text/plain")
        if u.path == "/api/events":
            return self.events(qs)
        m = re.fullmatch(r"/api/relay/([0-9a-f]{32})/(\d+)", u.path)
        if m:
            return self.relay_get(m.group(1), int(m.group(2)))
        if u.path in ("/", "/index.html"):
            return self.reply(200, body=open(os.path.join(HERE, "index.html"), "rb").read(), ctype="text/html; charset=utf-8")
        return self.reply(404, {"error": "not found"})

    def do_POST(self):
        u = urllib.parse.urlparse(self.path)
        try:
            data = self.body_json()
        except Exception:
            return self.reply(400, {"error": "bad request"})
        if u.path == "/api/join":
            return self.join(data)
        cid = self.auth(data.get("id"), data.get("token"))
        if not cid:
            return self.reply(401, {"error": "unknown device, reload the page"})
        if u.path == "/api/rename":
            return self.rename(cid, data)
        if u.path == "/api/signal":
            return self.signal(cid, data)
        return self.reply(404, {"error": "not found"})

    def do_PUT(self):
        m = re.fullmatch(r"/api/relay/([0-9a-f]{32})/(\d+)", urllib.parse.urlparse(self.path).path)
        if not m:
            return self.reply(404, {"error": "not found"})
        return self.relay_put(m.group(1), int(m.group(2)))

    def join(self, data):
        if not allow(self.ip(), "join", 30, 600):
            return self.reply(429, {"error": "slow down"})
        cid, tok = data.get("id"), data.get("token")
        with lock:
            if not self.auth(cid, tok):
                cid, tok = secrets.token_hex(12), secrets.token_urlsafe(24)
                clients[cid] = {"name": f"{secrets.choice(ADJ)} {secrets.choice(NOUN)}", "pin": new_pin(), "tok": h(tok), "last": time.time()}
            save()
            return self.reply(200, {**public(cid), "token": tok})

    def rename(self, cid, data):
        name = re.sub(r"\s+", " ", str(data.get("name", ""))).strip()[:24]
        if not name or not name.isprintable():
            return self.reply(400, {"error": "pick a name of 1 to 24 characters"})
        with lock:
            clients[cid]["name"] = name
            save()
            nets = {s.net for s in online.get(cid, [])}
            push(cid, {"type": "hello", "me": public(cid)})
        for n in nets:
            broadcast_peers(n)
        return self.reply(200, public(cid))

    def signal(self, cid, data):
        msg = data.get("msg") or {}
        kind, tid = msg.get("type"), str(msg.get("tid", ""))
        if kind not in ("offer", "accept", "decline", "cancel", "rtc", "relay", "done") or not re.fullmatch(r"[0-9a-f]{32}", tid):
            return self.reply(400, {"error": "bad message"})
        if kind == "offer":
            if not allow(cid, "offer", 20, 60) or not allow(self.ip(), "offer", 40, 60):
                return self.reply(429, {"error": "too many send requests, wait a minute"})
            target = find(data.get("to"))
            if not target:
                return self.reply(404, {"error": "nobody with that PIN is online right now"})
            if target == cid:
                return self.reply(400, {"error": "that is your own PIN"})
            files = [{"name": str(f.get("name", "file"))[:200], "size": int(f.get("size", 0)), "type": str(f.get("type", ""))[:100]}
                     for f in (msg.get("files") or [])][:500]
            if not files:
                return self.reply(400, {"error": "no files"})
            with lock:
                if tid in offers:
                    return self.reply(409, {"error": "duplicate"})
                offers[tid] = {"frm": cid, "to": target, "files": files, "accepted": False, "at": time.time()}
                for k in [k for k, o in offers.items() if o["at"] < time.time() - 86400]:
                    offers.pop(k, None)
            msg = {"type": "offer", "tid": tid, "files": files}
        else:
            with lock:
                o = offers.get(tid)
                if not o or cid not in (o["frm"], o["to"]):
                    return self.reply(404, {"error": "unknown transfer"})
                target = o["to"] if cid == o["frm"] else o["frm"]
                if kind == "accept":
                    if cid != o["to"]:
                        return self.reply(403, {"error": "not yours to accept"})
                    o["accepted"] = True
            if not online.get(target):
                return self.reply(404, {"error": "the other device went offline"})
            if kind == "rtc":
                msg = {k: msg[k] for k in ("type", "tid", "sdp", "ice") if k in msg}
            else:
                msg = {k: msg[k] for k in ("type", "tid", "i") if k in msg}
        with lock:
            push(target, {"type": "signal", "from": public(cid), "msg": msg})
            to = public(target)
        return self.reply(200, {"ok": True, "to": to})

    def events(self, qs):
        cid = self.auth(qs.get("id"), qs.get("token"))
        if not cid:
            return self.reply(401, {"error": "unknown device"})
        s = Session(cid, net_of(self.ip()))
        with lock:
            online.setdefault(cid, []).append(s)
            me = public(cid)
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Accel-Buffering", "no")
        self.end_headers()
        s.q.put({"type": "hello", "me": me})
        broadcast_peers(s.net)
        try:
            self.wfile.write(b"retry: 3000\n\n")
            while True:
                try:
                    ev = s.q.get(timeout=15)
                    self.wfile.write(b"data: " + json.dumps(ev).encode() + b"\n\n")
                except queue.Empty:
                    self.wfile.write(b": ping\n\n")
                self.wfile.flush()
        except Exception:
            pass
        finally:
            with lock:
                lst = online.get(cid, [])
                if s in lst:
                    lst.remove(s)
                if not lst:
                    online.pop(cid, None)
            broadcast_peers(s.net)

    # ---- relay: stream one accepted file from sender to receiver, nothing stored ----
    def offer_file(self, tid, i):
        with lock:
            o = offers.get(tid)
            if not o or not o["accepted"] or not (0 <= i < len(o["files"])):
                return None, None
            return o, o["files"][i]

    def relay_put(self, tid, i):
        o, f = self.offer_file(tid, i)
        if not o or self.auth(self.headers.get("X-Share-Id"), self.headers.get("X-Share-Token")) != o["frm"]:
            return self.reply(403, {"error": "no accepted transfer"})
        key = f"{tid}/{i}"
        with lock:
            if key in relays or len(relays) >= MAX_RELAYS:
                return self.reply(503, {"error": "relay busy, try again shortly"})
            r = relays[key] = Relay(f["size"])
        try:
            chunked = "chunked" in (self.headers.get("Transfer-Encoding") or "").lower()
            left = int(self.headers.get("Content-Length") or 0)
            sent = 0

            def put(b):
                if r.failed:
                    raise IOError("receiver gone")
                r.q.put(b, timeout=600)       # the receiver may need to click its download link

            if chunked:
                while True:
                    n = int(self.rfile.readline().split(b";")[0].strip() or b"0", 16)
                    if n == 0:
                        self.rfile.readline()
                        break
                    while n:
                        b = self.rfile.read(min(CHUNK, n))
                        n -= len(b)
                        sent += len(b)
                        put(b)
                    self.rfile.readline()
            else:
                while left:
                    b = self.rfile.read(min(CHUNK, left))
                    if not b:
                        raise IOError("sender gone")
                    left -= len(b)
                    sent += len(b)
                    put(b)
            put(None)
            r.done.wait(timeout=600)
            ok = r.done.is_set() and not r.failed and sent == f["size"]
            return self.reply(200 if ok else 502, {"ok": ok, "bytes": sent})
        except Exception as e:
            r.failed = True
            try:
                r.q.put_nowait(None)
            except Exception:
                pass
            return self.reply(502, {"error": str(e)})
        finally:
            with lock:
                relays.pop(key, None)

    def relay_get(self, tid, i):
        o, f = self.offer_file(tid, i)
        if not o:
            return self.reply(404, {"error": "no accepted transfer"})
        key = f"{tid}/{i}"
        deadline = time.time() + 600
        while True:
            with lock:
                r = relays.get(key)
                if r and not r.taken:
                    r.taken = True
                    break
            if time.time() > deadline:
                return self.reply(504, {"error": "sender did not start"})
            time.sleep(0.3)
        name = f["name"].replace("/", "_").replace("\\", "_")
        ascii_name = name.encode("ascii", "replace").decode().replace('"', "'").replace("?", "_")
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(f["size"]))
        self.send_header("Content-Disposition", f"attachment; filename=\"{ascii_name}\"; filename*=UTF-8''{urllib.parse.quote(name)}")
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Accel-Buffering", "no")
        self.end_headers()
        try:
            while True:
                b = r.q.get(timeout=600)
                if b is None:
                    break
                self.wfile.write(b)
            self.wfile.flush()
            r.done.set()
        except Exception:
            r.failed = True
            r.done.set()
            try:
                while True:
                    r.q.get_nowait()
            except Exception:
                pass


if __name__ == "__main__":
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    load()
    srv = ThreadingHTTPServer(("127.0.0.1", PORT), H)
    srv.daemon_threads = True
    srv.serve_forever()
