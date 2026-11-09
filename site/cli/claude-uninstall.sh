#!/usr/bin/env bash
# Removes what claude-install.sh set up: the claude-local profile only. Claude Code itself and your ~/.claude are never touched.
#   curl -fsSL https://kebin.dev/cli/claude-uninstall.sh | bash
set -euo pipefail
say() { printf '\033[1;33m%s\033[0m\n' "$*"; }

say "claude-local"
rm -f "$HOME/.local/bin/claude-local"
rm -rf "$HOME/.claude-local"
# the key file is shared with codex-local; keep it while that is still installed
[ -e "$HOME/.local/bin/codex-local" ] || rm -f "$HOME/.config/kebin/aibox.env"
rmdir "$HOME/.config/kebin" 2>/dev/null || true
echo "removed claude-local, its settings and history. Claude Code itself and your normal 'claude' are untouched."
say "done"
