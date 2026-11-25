#!/usr/bin/env python3
"""Gemini-API front for llama-swap, so Google's Antigravity CLI (agy) can run on the local models.

agy only talks the Gemini protocol to a custom endpoint (GOOGLE_GEMINI_BASE_URL). This service accepts
  POST /v1beta/models/<model>:streamGenerateContent?alt=sse   (what agy uses)
  POST /v1beta/models/<model>:generateContent
translates them to an OpenAI chat-completions request for llama-swap, and translates the answer back:
text, thinking (as `thought: true` parts) and tool calls (functionCall / functionResponse).

agy only accepts its own built-in model names, so every requested model is answered by AGY_MODEL
unless the name is itself a llama-swap model id. nginx checks the API key (x-goog-api-key) before
anything reaches this port; the upstream is on the LAN and needs no key.
Stdlib only. Config through the environment:
  AGY_UPSTREAM  default http://10.0.10.30:8086/v1/chat/completions
  AGY_MODEL     default qwen3.8-27b
  AGY_LISTEN    default 0.0.0.0:8097
  AGY_UPSTREAM_KEY  optional bearer key for the upstream (only needed when testing against https://ai.kebin.dev)
"""
import http.server, json, os, re, sys, time, uuid, urllib.request, urllib.error

UPSTREAM = os.environ.get("AGY_UPSTREAM", "http://10.0.10.30:8086/v1/chat/completions")
MODEL = os.environ.get("AGY_MODEL", "qwen3.8-27b")
HOST, PORT = os.environ.get("AGY_LISTEN", "0.0.0.0:8097").rsplit(":", 1)
UP_HEADERS = {"Content-Type": "application/json"}
if os.environ.get("AGY_UPSTREAM_KEY"):
    UP_HEADERS["Authorization"] = "Bearer " + os.environ["AGY_UPSTREAM_KEY"]
ROUTE = re.compile(r"^/v1beta/models/([^/:]+):(streamGenerateContent|generateContent)$")
_local_models, _local_models_at = set(), 0.0


def log(*a):
    print(time.strftime("%H:%M:%S"), *a, file=sys.stderr, flush=True)


def local_models():
    """llama-swap model ids, cached for a minute (lets agy ask for a local model by its exact id)."""
    global _local_models, _local_models_at
    if time.time() - _local_models_at > 60:
        try:
            url = UPSTREAM.rsplit("/chat/completions", 1)[0] + "/models"
            with urllib.request.urlopen(urllib.request.Request(url, headers=UP_HEADERS), timeout=5) as r:
                _local_models = {m["id"] for m in json.load(r)["data"]}
        except Exception:
            pass
        _local_models_at = time.time()
    return _local_models


def pick_model(requested):
    return requested if requested in local_models() else MODEL


# ---------------------------------------------------------------------------------------------- request
def clean_schema(s):
    """Gemini schemas -> JSON Schema: drop $schema, lowercase the OpenAPI-style type names (STRING -> string)."""
    if isinstance(s, dict):
        out = {}
        for k, v in s.items():
            if k == "$schema":
                continue
            if k == "type" and isinstance(v, str):
                v = v.lower()
            out[k] = clean_schema(v)
        return out
    if isinstance(s, list):
        return [clean_schema(x) for x in s]
    return s


def text_of(parts):
    return "".join(p.get("text", "") for p in parts if "text" in p and not p.get("thought"))


def to_openai(body, model):
    msgs, pending = [], []  # pending: [(id, name)] function calls waiting for their responses
    sys_parts = (body.get("systemInstruction") or {}).get("parts") or []
    if text_of(sys_parts):
        msgs.append({"role": "system", "content": text_of(sys_parts)})
    for ti, turn in enumerate(body.get("contents") or []):
        role, parts = turn.get("role", "user"), turn.get("parts") or []
        if role == "model":
            text = text_of([p for p in parts if "functionResponse" not in p])
            msg = {"role": "assistant", "content": text or None}
            calls = []
            for i, p in enumerate(parts):
                fc = p.get("functionCall")
                if fc:
                    cid = fc.get("id") or f"call_{ti}_{i}"
                    calls.append({"id": cid, "type": "function",
                                  "function": {"name": fc["name"], "arguments": json.dumps(fc.get("args") or {})}})
                    pending.append((cid, fc["name"]))
            if calls:
                msg["tool_calls"] = calls
            if msg["content"] is not None or calls:
                msgs.append(msg)
            # agy sends its tool results in a *model* turn (stock Gemini puts them in a user turn): fall through so
            # the functionResponse parts below become tool messages either way; plain model text was handled above
            parts = [p for p in parts if "functionResponse" in p]
            if not parts:
                continue
        # function responses become tool messages, the rest a user message
        content = []
        for p in parts:
            fr = p.get("functionResponse")
            if fr:
                cid = fr.get("id")
                if not cid:
                    match = next((c for c in pending if c[1] == fr.get("name")), pending[0] if pending else None)
                    cid = match[0] if match else f"call_{uuid.uuid4().hex[:8]}"
                pending = [c for c in pending if c[0] != cid]
                resp = fr.get("response")
                out = resp.get("output") if isinstance(resp, dict) and isinstance(resp.get("output"), str) else json.dumps(resp)
                msgs.append({"role": "tool", "tool_call_id": cid, "content": out})
            elif "text" in p and not p.get("thought"):
                content.append({"type": "text", "text": p["text"]})
            elif "inlineData" in p:
                d = p["inlineData"]
                content.append({"type": "image_url", "image_url": {"url": f"data:{d.get('mimeType', 'image/png')};base64,{d.get('data', '')}"}})
        if content:
            msgs.append({"role": "user", "content": content if any(c["type"] != "text" for c in content)
                         else "".join(c["text"] for c in content)})
    req = {"model": model, "messages": msgs}
    tools = [{"type": "function", "function": {"name": f["name"], "description": f.get("description", ""),
                                               "parameters": clean_schema(f.get("parametersJsonSchema") or f.get("parameters") or {"type": "object", "properties": {}})}}
             for t in body.get("tools") or [] for f in t.get("functionDeclarations") or []]
    if tools:
        req["tools"] = tools
    gc = body.get("generationConfig") or {}
    for g, o in (("maxOutputTokens", "max_tokens"), ("temperature", "temperature"), ("topP", "top_p"), ("topK", "top_k"), ("stopSequences", "stop")):
        if g in gc:
            req[o] = gc[g]
    level = str((gc.get("thinkingConfig") or {}).get("thinkingLevel", "")).upper()
    if level in ("MINIMAL", "LOW") or (gc.get("thinkingConfig") or {}).get("thinkingBudget") == 0:
        req["chat_template_kwargs"] = {"enable_thinking": False}
    return req


# --------------------------------------------------------------------------------------------- response
FINISH = {"stop": "STOP", "length": "MAX_TOKENS", "tool_calls": "STOP", "content_filter": "SAFETY"}


def gemini_chunk(parts, rid, model, finish=None, usage=None):
    cand = {"content": {"role": "model", "parts": parts}, "index": 0}
    if finish:
        cand["finishReason"] = finish
    out = {"candidates": [cand], "modelVersion": model, "responseId": rid}
    if usage:
        out["usageMetadata"] = {"promptTokenCount": usage.get("prompt_tokens", 0),
                                "candidatesTokenCount": usage.get("completion_tokens", 0),
                                "totalTokenCount": usage.get("total_tokens", 0)}
    return out


def call_parts(calls):
    parts = []
    for c in sorted(calls.values(), key=lambda c: c["index"]):
        try:
            args = json.loads(c["args"] or "{}")
        except json.JSONDecodeError:
            args = {"_raw": c["args"]}
        parts.append({"functionCall": {"id": c["id"], "name": c["name"], "args": args}})
    return parts


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def send_json(self, code, obj):
        data = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def error(self, code, msg):
        status = {400: "INVALID_ARGUMENT", 404: "NOT_FOUND", 502: "UNAVAILABLE"}.get(code, "INTERNAL")
        self.send_json(code, {"error": {"code": code, "message": msg, "status": status}})

    def do_GET(self):
        if self.path.split("?")[0] in ("/health", "/"):
            return self.send_json(200, {"ok": True, "model": MODEL})
        self.error(404, "not found")

    def do_POST(self):
        m = ROUTE.match(self.path.split("?")[0])
        if not m:
            return self.error(404, f"unsupported path {self.path}")
        stream = m.group(2) == "streamGenerateContent"
        try:
            body = json.loads(self.rfile.read(int(self.headers.get("Content-Length") or 0)) or b"{}")
        except json.JSONDecodeError:
            return self.error(400, "body is not JSON")
        if os.environ.get("AGY_DEBUG"):
            log("turns:", json.dumps([(t.get("role"), [sorted(k for k in pt if k != "text") or ["text"] for pt in t.get("parts", [])])
                                      for t in body.get("contents", [])]))
        model = pick_model(m.group(1))
        req = to_openai(body, model)
        req["stream"] = True
        req["stream_options"] = {"include_usage": True}
        rid = uuid.uuid4().hex[:16]
        log(f"{m.group(1)} -> {model} stream={stream} msgs={len(req['messages'])} tools={len(req.get('tools', []))}")
        try:
            up = urllib.request.urlopen(urllib.request.Request(UPSTREAM, data=json.dumps(req).encode(),
                                                               headers=UP_HEADERS), timeout=1800)
        except urllib.error.HTTPError as e:
            detail = e.read()[:500].decode("utf-8", "replace")
            log("upstream error", e.code, detail)
            return self.error(e.code if 400 <= e.code < 600 else 502, f"model server: {detail}")
        except Exception as e:
            return self.error(502, f"model server unreachable: {e}")

        if stream:
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "close")
            self.end_headers()
            self.close_connection = True

        calls, texts, thoughts, finish, usage = {}, [], [], None, None
        for raw in up:
            line = raw.decode("utf-8", "replace").strip()
            if not line.startswith("data:"):
                continue
            data = line[5:].strip()
            if data == "[DONE]":
                break
            try:
                ev = json.loads(data)
            except json.JSONDecodeError:
                continue
            usage = ev.get("usage") or usage
            for ch in ev.get("choices") or []:
                d = ch.get("delta") or {}
                parts = []
                if d.get("reasoning_content"):
                    parts.append({"text": d["reasoning_content"], "thought": True})
                    thoughts.append(d["reasoning_content"])
                if d.get("content"):
                    parts.append({"text": d["content"]})
                    texts.append(d["content"])
                for tc in d.get("tool_calls") or []:
                    c = calls.setdefault(tc.get("index", 0), {"index": tc.get("index", 0), "id": "", "name": "", "args": ""})
                    c["id"] = tc.get("id") or c["id"] or f"call_{uuid.uuid4().hex[:8]}"
                    fn = tc.get("function") or {}
                    c["name"] += fn.get("name") or ""
                    c["args"] += fn.get("arguments") or ""
                if ch.get("finish_reason"):
                    finish = FINISH.get(ch["finish_reason"], "STOP")
                if stream and parts:
                    self.wfile.write(b"data: " + json.dumps(gemini_chunk(parts, rid, model)).encode() + b"\r\n\r\n")
                    self.wfile.flush()
        up.close()
        tail = call_parts(calls)
        if stream:
            self.wfile.write(b"data: " + json.dumps(gemini_chunk(tail or [{"text": ""}], rid, model, finish or "STOP", usage)).encode() + b"\r\n\r\n")
            self.wfile.flush()
        else:
            parts = ([{"text": "".join(thoughts), "thought": True}] if thoughts else []) + \
                    ([{"text": "".join(texts)}] if texts else []) + tail
            self.send_json(200, gemini_chunk(parts or [{"text": ""}], rid, model, finish or "STOP", usage))
        log(f"done: {len(''.join(texts))} chars, {len(calls)} tool calls, finish={finish}")


if __name__ == "__main__":
    log(f"agy-gateway on {HOST}:{PORT} -> {UPSTREAM} (default model {MODEL})")
    http.server.ThreadingHTTPServer((HOST, int(PORT)), Handler).serve_forever()
