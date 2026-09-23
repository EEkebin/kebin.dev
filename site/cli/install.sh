#!/usr/bin/env bash
# Installs the OpenCode CLI and points it at the kebin.dev model server.
#   curl -fsSL https://kebin.dev/cli/install.sh | bash
#   AIBOX_KEY=... curl -fsSL https://kebin.dev/cli/install.sh | bash   (non-interactive)
set -euo pipefail
API="https://ai.kebin.dev/v1"
SEARCH="https://search.kebin.dev"
CFG_DIR="$HOME/.config/opencode"
CFG="$CFG_DIR/opencode.json"

say() { printf '\033[1;33m%s\033[0m\n' "$*"; }

say "1/3  OpenCode"
if command -v opencode >/dev/null 2>&1; then
  echo "already installed: $(opencode --version 2>/dev/null | head -1)"
else
  curl -fsSL https://opencode.ai/install | bash
  export PATH="$HOME/.opencode/bin:$PATH"
fi

say "2/3  API key"
KEY="${AIBOX_KEY:-}"
if [ -z "$KEY" ] && [ -t 0 ]; then read -r -p "Paste the ai.kebin.dev API key: " KEY; fi
if [ -z "$KEY" ] && [ -r /dev/tty ]; then read -r -p "Paste the ai.kebin.dev API key: " KEY < /dev/tty; fi
[ -n "$KEY" ] || { echo "no key given; set AIBOX_KEY=... and rerun" >&2; exit 1; }
code=$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $KEY" "$API/models" || true)
[ "$code" = 200 ] || { echo "key rejected by $API (HTTP $code)" >&2; exit 1; }
echo "key accepted"
scode=$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $KEY" "$SEARCH/health" || true)
[ "$scode" = 200 ] && echo "web search reachable" || echo "warning: $SEARCH answered HTTP $scode, web search may not work right now"

say "3/3  config -> $CFG"
mkdir -p "$CFG_DIR"
[ -f "$CFG" ] && cp "$CFG" "$CFG.bak.$(date +%s)"
cat > "$CFG" <<JSON
{
  "\$schema": "https://opencode.ai/config.json",
  "model": "aibox/qwen3.5-9b",
  "provider": {
    "aibox": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "kebin.dev (ai.kebin.dev)",
      "options": { "baseURL": "$API", "apiKey": "$KEY" },
      "models": {
        "qwen3.5-9b": {
          "name": "Qwen3.5 9B (vision, 128K)",
          "attachment": true,
          "modalities": { "input": ["text", "image"], "output": ["text"] },
          "limit": { "context": 131072, "output": 16384 }
        },
        "qwen3.8-27b": {
          "name": "Qwen3.8 27B (vision, 32K)",
          "attachment": true,
          "modalities": { "input": ["text", "image"], "output": ["text"] },
          "limit": { "context": 32768, "output": 8192 }
        }
      }
    }
  },
  "mcp": {
    "searxng": {
      "type": "remote",
      "url": "$SEARCH/mcp",
      "headers": { "Authorization": "Bearer $KEY" },
      "oauth": false,
      "enabled": true,
      "timeout": 60000
    }
  },
  "permission": { "webfetch": "allow", "websearch": "deny", "searxng_*": "allow" },
  "lsp": true
}
JSON
chmod 600 "$CFG"
echo
say "done. open a project folder and run:  opencode"
echo "switch models inside OpenCode with /models. Web search (searxng_web_search) and page fetch are on. Re-run this script any time to update."
command -v opencode >/dev/null 2>&1 || echo "note: open a new terminal so 'opencode' is on your PATH."
