#!/usr/bin/env bash
# Sets up `claude-local`: Claude Code running on the kebin.dev model server instead of Anthropic's cloud.
# Your normal `claude` is left alone; claude-local keeps its own settings and history in ~/.claude-local.
# It only adds the profile: Claude Code itself has to be installed already (https://code.claude.com/docs).
#   curl -fsSL https://kebin.dev/cli/claude-install.sh | bash
#   AIBOX_KEY=... curl -fsSL https://kebin.dev/cli/claude-install.sh | bash   (non-interactive)
set -euo pipefail
API="https://ai.kebin.dev/v1"
SEARCH="https://search.kebin.dev"
MODEL="qwen3.8-27b"
ENV_DIR="$HOME/.config/kebin"
ENV_FILE="$ENV_DIR/aibox.env"
HOME_DIR="$HOME/.claude-local"
BIN_DIR="$HOME/.local/bin"

say() { printf '\033[1;33m%s\033[0m\n' "$*"; }

say "1/3  Claude Code"
command -v claude >/dev/null 2>&1 || { echo "Claude Code isn't installed. Install it first (https://code.claude.com/docs), then rerun this script." >&2; exit 1; }
echo "found: $(claude --version 2>/dev/null | head -1)"

say "2/3  API key"
KEY="${AIBOX_KEY:-}"
if [ -z "$KEY" ] && [ -t 0 ]; then read -r -p "Paste the ai.kebin.dev API key: " KEY; fi
if [ -z "$KEY" ] && [ -r /dev/tty ]; then read -r -p "Paste the ai.kebin.dev API key: " KEY < /dev/tty; fi
[ -n "$KEY" ] || { echo "no key given; set AIBOX_KEY=... and rerun" >&2; exit 1; }
case "$KEY" in *[!A-Za-z0-9._~+/=-]*) echo "that key has unexpected characters; paste it exactly as shown on kebin.dev/cli" >&2; exit 1 ;; esac
code=$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $KEY" "$API/models" || true)
[ "$code" = 200 ] || { echo "key rejected by $API (HTTP $code)" >&2; exit 1; }
echo "key accepted"

say "3/3  claude-local"
mkdir -p "$ENV_DIR" "$HOME_DIR" "$BIN_DIR"
( umask 077; printf "AIBOX_KEY='%s'\n" "$KEY" > "$ENV_FILE" ); chmod 600 "$ENV_FILE"
# Anthropic's hosted web search doesn't exist on a local model; search goes through search.kebin.dev instead
[ -f "$HOME_DIR/settings.json" ] || printf '{\n  "permissions": { "deny": ["WebSearch"] }\n}\n' > "$HOME_DIR/settings.json"
CLAUDE_CONFIG_DIR="$HOME_DIR" claude mcp remove -s user searxng >/dev/null 2>&1 || true
if CLAUDE_CONFIG_DIR="$HOME_DIR" claude mcp add --transport http -s user searxng "$SEARCH/mcp" --header "Authorization: Bearer $KEY" >/dev/null 2>&1; then
  echo "web search (searxng) added"
else
  echo "warning: couldn't add the web search tool; claude-local still works without it"
fi
cat > "$BIN_DIR/claude-local" <<'SH'
#!/bin/sh
# kebin.dev: Claude Code on the model server at ai.kebin.dev. Settings and history live in ~/.claude-local.
. "$HOME/.config/kebin/aibox.env"
unset ANTHROPIC_API_KEY CLAUDE_CODE_USE_BEDROCK CLAUDE_CODE_USE_VERTEX CLAUDE_CODE_USE_FOUNDRY
export ANTHROPIC_BASE_URL="https://ai.kebin.dev"
export ANTHROPIC_AUTH_TOKEN="$AIBOX_KEY"
export CLAUDE_CONFIG_DIR="$HOME/.claude-local"
export ANTHROPIC_MODEL="qwen3.8-27b"
export ANTHROPIC_DEFAULT_OPUS_MODEL="qwen3.8-27b"
export ANTHROPIC_DEFAULT_SONNET_MODEL="qwen3.8-27b"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="qwen3.8-27b"
export CLAUDE_CODE_MAX_CONTEXT_TOKENS=262144
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
exec claude "$@"
SH
chmod 755 "$BIN_DIR/claude-local"
echo
say "done. open a project folder and run:  claude-local"
echo "Uses $MODEL on ai.kebin.dev with web search. Your normal 'claude' still uses Anthropic. Re-run this script any time to update."
case ":$PATH:" in *":$BIN_DIR:"*) ;; *) echo "note: add $BIN_DIR to your PATH (or open a new terminal) so 'claude-local' is found." ;; esac
