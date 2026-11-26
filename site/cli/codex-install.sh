#!/usr/bin/env bash
# Sets up `codex-local`: Codex running on the kebin.dev model server instead of OpenAI's cloud.
# Your normal `codex` is left alone; codex-local keeps its own settings and history in ~/.codex-local.
# It only adds the profile: Codex itself has to be installed already (https://developers.openai.com/codex).
#   curl -fsSL https://kebin.dev/cli/codex-install.sh | bash
#   AIBOX_KEY=... curl -fsSL https://kebin.dev/cli/codex-install.sh | bash   (non-interactive)
set -euo pipefail
API="https://ai.kebin.dev/v1"
MODEL="qwen3.8-27b"
ENV_DIR="$HOME/.config/kebin"
ENV_FILE="$ENV_DIR/aibox.env"
HOME_DIR="$HOME/.codex-local"
BIN_DIR="$HOME/.local/bin"

say() { printf '\033[1;33m%s\033[0m\n' "$*"; }

say "1/3  Codex"
command -v codex >/dev/null 2>&1 || { echo "Codex isn't installed. Install it first (https://developers.openai.com/codex), then rerun this script." >&2; exit 1; }
echo "found: $(codex --version 2>/dev/null | head -1)"

say "2/3  API key"
KEY="${AIBOX_KEY:-}"
if [ -z "$KEY" ] && [ -t 0 ]; then read -r -p "Paste the ai.kebin.dev API key: " KEY; fi
if [ -z "$KEY" ] && [ -r /dev/tty ]; then read -r -p "Paste the ai.kebin.dev API key: " KEY < /dev/tty; fi
[ -n "$KEY" ] || { echo "no key given; set AIBOX_KEY=... and rerun" >&2; exit 1; }
case "$KEY" in *[!A-Za-z0-9._~+/=-]*) echo "that key has unexpected characters; paste it exactly as shown on kebin.dev/cli" >&2; exit 1 ;; esac
code=$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $KEY" "$API/models" || true)
[ "$code" = 200 ] || { echo "key rejected by $API (HTTP $code)" >&2; exit 1; }
echo "key accepted"

say "3/3  codex-local"
mkdir -p "$ENV_DIR" "$HOME_DIR" "$BIN_DIR"
( umask 077; printf "AIBOX_KEY='%s'\n" "$KEY" > "$ENV_FILE" ); chmod 600 "$ENV_FILE"
cat > "$HOME_DIR/config.toml" <<TOML
# kebin.dev: written by codex-install.sh
model = "$MODEL"
model_provider = "aibox"
model_context_window = 262144

[model_providers.aibox]
name = "kebin.dev (ai.kebin.dev)"
base_url = "$API"
env_key = "AIBOX_KEY"
wire_api = "responses"
TOML
cat > "$BIN_DIR/codex-local" <<'SH'
#!/bin/sh
# kebin.dev: Codex on the model server at ai.kebin.dev. Settings and history live in ~/.codex-local.
. "$HOME/.config/kebin/aibox.env"
export AIBOX_KEY
export CODEX_HOME="$HOME/.codex-local"
exec codex "$@"
SH
chmod 755 "$BIN_DIR/codex-local"
echo
say "done. open a project folder and run:  codex-local"
echo "Uses $MODEL on ai.kebin.dev. No web search here (Codex doesn't hand search tools to local models). Your normal 'codex' still uses OpenAI. Re-run this script any time to update."
case ":$PATH:" in *":$BIN_DIR:"*) ;; *) echo "note: add $BIN_DIR to your PATH (or open a new terminal) so 'codex-local' is found." ;; esac
