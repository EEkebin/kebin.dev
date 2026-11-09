#!/usr/bin/env bash
# Removes what codex-install.sh set up: the codex-local profile only. Codex itself and your ~/.codex are never touched.
#   curl -fsSL https://kebin.dev/cli/codex-uninstall.sh | bash
set -euo pipefail
say() { printf '\033[1;33m%s\033[0m\n' "$*"; }

say "codex-local"
rm -f "$HOME/.local/bin/codex-local"
rm -rf "$HOME/.codex-local"
# the key file is shared with claude-local; keep it while that is still installed
[ -e "$HOME/.local/bin/claude-local" ] || rm -f "$HOME/.config/kebin/aibox.env"
rmdir "$HOME/.config/kebin" 2>/dev/null || true
echo "removed codex-local, its settings and history. Codex itself and your normal 'codex' are untouched."
say "done"
