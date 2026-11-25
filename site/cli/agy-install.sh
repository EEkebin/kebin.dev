#!/usr/bin/env bash
# Sets up `agy-local`: Google's Antigravity CLI (agy) running on the kebin.dev model server instead of Google's cloud.
# Your normal `agy` is left alone; agy-local keeps its own settings and history in ~/.agy-local.
# It only adds the profile: the Antigravity CLI itself has to be installed already (https://antigravity.google/docs/install).
#   curl -fsSL https://kebin.dev/cli/agy-install.sh | bash
#   AIBOX_KEY=... curl -fsSL https://kebin.dev/cli/agy-install.sh | bash   (non-interactive)
#
# How: agy can use a custom Gemini-API endpoint (modelProvider "gemini" + GOOGLE_GEMINI_BASE_URL). ai.kebin.dev/v1beta/
# is a small translator in front of the model server, and it answers every model name with qwen3.8-27b, because agy only
# accepts its own built-in model names. Web search comes from search.kebin.dev over MCP (agy's own search needs a Google login).
set -euo pipefail
API="https://ai.kebin.dev/v1"
BASE="https://ai.kebin.dev"
SEARCH="https://search.kebin.dev"
ENV_DIR="$HOME/.config/kebin"
ENV_FILE="$ENV_DIR/aibox.env"
HOME_DIR="$HOME/.agy-local"
BIN_DIR="$HOME/.local/bin"

say() { printf '\033[1;33m%s\033[0m\n' "$*"; }

say "1/3  Antigravity CLI"
command -v agy >/dev/null 2>&1 || { echo "The Antigravity CLI (agy) isn't installed. Install it first (https://antigravity.google/docs/install), then rerun this script." >&2; exit 1; }
echo "found: agy $(agy --version 2>/dev/null | head -1)"

say "2/3  API key"
KEY="${AIBOX_KEY:-}"
if [ -z "$KEY" ] && [ -t 0 ]; then read -r -p "Paste the ai.kebin.dev API key: " KEY; fi
if [ -z "$KEY" ] && [ -r /dev/tty ]; then read -r -p "Paste the ai.kebin.dev API key: " KEY < /dev/tty; fi
[ -n "$KEY" ] || { echo "no key given; set AIBOX_KEY=... and rerun" >&2; exit 1; }
case "$KEY" in *[!A-Za-z0-9._~+/=-]*) echo "that key has unexpected characters; paste it exactly as shown on kebin.dev/cli" >&2; exit 1 ;; esac
code=$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $KEY" "$API/models" || true)
[ "$code" = 200 ] || { echo "key rejected by $API (HTTP $code)" >&2; exit 1; }
echo "key accepted"

say "3/3  agy-local"
mkdir -p "$ENV_DIR" "$HOME_DIR/antigravity-cli" "$BIN_DIR"
( umask 077; printf "AIBOX_KEY='%s'\n" "$KEY" > "$ENV_FILE" ); chmod 600 "$ENV_FILE"
[ -f "$HOME_DIR/antigravity-cli/settings.json" ] || printf '{\n  "modelProvider": "gemini"\n}\n' > "$HOME_DIR/antigravity-cli/settings.json"
if agy --gemini_dir="$HOME_DIR" mcp add --header "Authorization: Bearer $KEY" searxng "$SEARCH/mcp" >/dev/null 2>&1; then
  echo "web search (searxng) added"
else
  echo "warning: couldn't add the web search tool; agy-local still works without it"
fi
# agy refuses model names it doesn't know, so use one of its own; the server answers it with qwen3.8-27b either way
MODEL=$(GOOGLE_GEMINI_BASE_URL="$BASE" GEMINI_API_KEY="$KEY" agy --gemini_dir="$HOME_DIR" models 2>/dev/null | awk 'NF {print $1; exit}' || true)
MODEL=${MODEL:-gemini-3.8-flash-high}
cat > "$BIN_DIR/agy-local" <<SH
#!/bin/sh
# kebin.dev: the Antigravity CLI on the model server at ai.kebin.dev. Settings and history live in ~/.agy-local.
. "\$HOME/.config/kebin/aibox.env"
export GOOGLE_GEMINI_BASE_URL="$BASE"
export GEMINI_API_KEY="\$AIBOX_KEY"
case "\${1:-}" in
  mcp|models|plugin|plugins|update|install|changelog|help|agent|agents|acp|remote-control|mic-serve)
    exec agy --gemini_dir="\$HOME/.agy-local" "\$@" ;;
esac
exec agy --gemini_dir="\$HOME/.agy-local" --model "$MODEL" "\$@"
SH
chmod 755 "$BIN_DIR/agy-local"
echo
say "done. open a project folder and run:  agy-local"
echo "Uses qwen3.8-27b on ai.kebin.dev with web search (agy shows it as '$MODEL'). Your normal 'agy' still uses Google. Re-run this script any time to update."
case ":$PATH:" in *":$BIN_DIR:"*) ;; *) echo "note: add $BIN_DIR to your PATH (or open a new terminal) so 'agy-local' is found." ;; esac
