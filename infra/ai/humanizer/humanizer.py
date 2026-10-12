#!/usr/bin/env python3
"""Humanizer page: paste a draft, get it rewritten by the `humanizer` model in llama-swap.

The model is a plain completion model with a fixed prompt (instr + "\n\n" + draft + sep, from the model's
prompt_format.json), so the prompt is built here and the browser only ever sends the draft. The rewrite is
streamed back as server-sent events straight from llama-swap's /v1/completions.
"""
import hashlib
import http.client
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
FORMAT = os.environ.get("HUMANIZER_FORMAT", "/mnt/storage/AI/models/humanizer/prompt_format.json")
UPSTREAM = os.environ.get("HUMANIZER_UPSTREAM", "127.0.0.1:8080")
MODEL = os.environ.get("HUMANIZER_MODEL", "humanizer")
LISTEN = int(os.environ.get("HUMANIZER_PORT", "8095"))
MAX_CHARS = 12000      # the model has an 8192-token window for instruction + draft + rewrite

with open(FORMAT, encoding="utf-8") as f:
    PF = json.load(f)


def build_prompt(draft):
    return PF["instr"] + "\n\n" + draft.strip() + PF["sep"]


# the model card's self-check: the prompt for the draft "X" must hash to the published fingerprint
_check = hashlib.sha256(build_prompt("X").encode()).hexdigest()[:16]
if _check != PF.get("fingerprint"):
    raise SystemExit(f"prompt_format.json fingerprint mismatch: {_check} != {PF.get('fingerprint')}")

with open(os.path.join(HERE, "index.html"), "rb") as f:
    PAGE = f.read()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "humanizer"

    def log_message(self, fmt, *args):
        pass

    def send_plain(self, code, body, ctype="text/plain; charset=utf-8"):
        if isinstance(body, str):
            body = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?")[0]
        if path in ("/", "/index.html"):
            self.send_plain(200, PAGE, "text/html; charset=utf-8")
        elif path == "/health":
            self.send_plain(200, "ok")
        else:
            self.send_plain(404, "not found")

    def do_POST(self):
        if self.path.split("?")[0] != "/api/rewrite":
            return self.send_plain(404, "not found")
        try:
            n = int(self.headers.get("Content-Length") or 0)
            draft = json.loads(self.rfile.read(min(n, 200000)) or b"{}").get("text", "")
        except (ValueError, AttributeError):
            return self.send_plain(400, "bad request")
        if not isinstance(draft, str) or not draft.strip():
            return self.send_plain(400, "empty draft")
        if len(draft) > MAX_CHARS:
            return self.send_plain(413, f"draft is longer than {MAX_CHARS} characters, split it up")

        # sampling from the model card: temp 1.0, top-p 0.95, top-k/min-p/repeat penalty off, stop on EOS only
        body = json.dumps({
            "model": MODEL, "prompt": build_prompt(draft), "max_tokens": 2048, "stream": True,
            "temperature": 1.0, "top_p": 0.95, "top_k": 0, "min_p": 0.0, "repeat_penalty": 1.0,
        })
        up = http.client.HTTPConnection(UPSTREAM, timeout=600)
        try:
            up.request("POST", "/v1/completions", body, {"Content-Type": "application/json"})
            r = up.getresponse()
            if r.status != 200:
                return self.send_plain(502, f"model server answered {r.status}: {r.read(500).decode(errors='replace')}")
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Accel-Buffering", "no")
            self.send_header("Connection", "close")
            self.end_headers()
            while True:
                line = r.readline()
                if not line:
                    break
                self.wfile.write(line)
                if line == b"\n":
                    self.wfile.flush()
            self.close_connection = True
        except (BrokenPipeError, ConnectionResetError):
            pass        # the browser hit Stop; closing upstream makes llama-server cancel the generation
        except OSError as e:
            try:
                self.send_plain(502, f"model server unreachable: {e}")
            except OSError:
                pass
        finally:
            up.close()


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", LISTEN), Handler).serve_forever()
