#!/usr/bin/env bash
# Removes what install.sh set up.
#   curl -fsSL https://kebin.dev/cli/uninstall.sh | bash            # remove the kebin.dev profile only
#   curl -fsSL https://kebin.dev/cli/uninstall.sh | bash -s -- --all # also remove OpenCode itself
set -euo pipefail
CFG_DIR="$HOME/.config/opencode"
CFG="$CFG_DIR/opencode.json"
ALL=0; [ "${1:-}" = "--all" ] && ALL=1
say() { printf '\033[1;33m%s\033[0m\n' "$*"; }

say "1/2  kebin.dev profile"
if [ -f "$CFG" ]; then
  BAK=$(ls -t "$CFG".bak.* 2>/dev/null | head -1 || true)
  if [ -n "$BAK" ]; then
    mv -f "$BAK" "$CFG"; rm -f "$CFG".bak.* 2>/dev/null || true
    echo "restored your previous config from $(basename "$BAK")"
  elif python3 - "$CFG" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
hit = False
prov = d.get("provider", {})
if "aibox" in prov:
    hit = True; del prov["aibox"]
    if str(d.get("model", "")).startswith("aibox/"): d.pop("model", None)
    if not prov: d.pop("provider", None)
mcp = d.get("mcp", {})
if "searxng" in mcp:
    hit = True; del mcp["searxng"]
    if not mcp: d.pop("mcp", None)
perm = d.get("permission", {})
for k in ("searxng_*", "webfetch", "websearch"):
    if k in perm: hit = True; del perm[k]
if "permission" in d and not perm: d.pop("permission", None)
if not hit: sys.exit(1)
json.dump(d, open(p, "w"), indent=2)
PY
  then echo "removed the kebin.dev provider and search tool from $CFG"
  else echo "no kebin.dev profile found in $CFG, left untouched"
  fi
else
  echo "no OpenCode config found"
fi

say "2/2  OpenCode itself"
if [ "$ALL" = 1 ]; then
  rm -rf "$HOME/.opencode"
  for f in "$HOME/.local/bin/opencode" /usr/local/bin/opencode; do [ -L "$f" ] || [ -f "$f" ] && rm -f "$f" 2>/dev/null || true; done
  command -v npm >/dev/null 2>&1 && npm ls -g opencode-ai >/dev/null 2>&1 && npm uninstall -g opencode-ai >/dev/null 2>&1 || true
  command -v brew >/dev/null 2>&1 && brew list opencode >/dev/null 2>&1 && brew uninstall opencode >/dev/null 2>&1 || true
  rm -rf "$HOME/.local/share/opencode" "$HOME/.cache/opencode" "$CFG_DIR" 2>/dev/null || true
  echo "OpenCode removed (binary, data, cache, config)"
else
  echo "left installed. Run again with --all to remove OpenCode too."
fi
say "done"
