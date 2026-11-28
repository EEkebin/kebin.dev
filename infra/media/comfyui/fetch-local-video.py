#!/usr/bin/env python3
"""Fetch the three weights selected by the installed ComfyUI LTX templates."""
import hashlib
import json
import subprocess
import sys
import urllib.request
from pathlib import Path

root = Path(sys.argv[1])
templates = next(root.glob(".venv/lib/python*/site-packages/comfyui_workflow_templates_json/templates"))
models = {}
for mode in ("text", "image"):
    workflow = json.loads((templates / f"ltxv_{mode}_to_video.json").read_text())
    for node in workflow["nodes"]:
        for model in node.get("properties", {}).get("models", []):
            models[model["name"]] = model

for model in models.values():
    dest = root / "models" / model["directory"] / model["name"]
    url = model["url"].split("?")[0]
    repo = url.split("huggingface.co/")[1].split("/resolve/")[0]
    with urllib.request.urlopen(f"https://huggingface.co/api/models/{repo}/tree/main?limit=1000") as response:
        files = json.load(response)
    digest = next(f["lfs"]["oid"] for f in files if f["path"] == model["name"])
    dest.parent.mkdir(exist_ok=True, parents=True)
    candidate = dest if dest.exists() else dest.with_suffix(".partial")
    if candidate != dest:
        subprocess.run(["curl", "-fsSL", "--retry", "3", "-C", "-", "-o", str(candidate), url], check=True)
    with candidate.open("rb") as handle:
        if hashlib.file_digest(handle, "sha256").hexdigest() != digest:
            raise ValueError(f"SHA-256 mismatch: {candidate}")
    if candidate != dest:
        candidate.rename(dest)
    print(dest.name, flush=True)
