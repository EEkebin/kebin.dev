#!/usr/bin/env bash
# Removes what agy-install.sh set up: the agy-local profile only. The Antigravity CLI itself and your ~/.gemini are never touched.
#   curl -fsSL https://kebin.dev/cli/agy-uninstall.sh | bash
set -euo pipefail
say() { printf '\033[1;33m%s\033[0m\n' "$*"; }

say "agy-local"
rm -f "$HOME/.local/bin/agy-local"
rm -rf "$HOME/.agy-local"
# the key file is shared with claude-local and codex-local; keep it while either is still installed
[ -e "$HOME/.local/bin/claude-local" ] || [ -e "$HOME/.local/bin/codex-local" ] || rm -f "$HOME/.config/kebin/aibox.env"
rmdir "$HOME/.config/kebin" 2>/dev/null || true
echo "removed agy-local, its settings and history. The Antigravity CLI and your normal 'agy' are untouched."
say "done"
