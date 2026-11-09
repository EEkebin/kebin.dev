#!/usr/bin/env bash
# Removes what codex-install.sh set up. Your normal `codex` settings in ~/.codex are never touched.
#   curl -fsSL https://kebin.dev/cli/codex-uninstall.sh | bash             # remove codex-local and its settings/history
#   curl -fsSL https://kebin.dev/cli/codex-uninstall.sh | bash -s -- --all  # also remove Codex itself
set -euo pipefail
ALL=0; [ "${1:-}" = "--all" ] && ALL=1
say() { printf '\033[1;33m%s\033[0m\n' "$*"; }

say "1/2  codex-local"
rm -f "$HOME/.local/bin/codex-local"
rm -rf "$HOME/.codex-local"
# the key file is shared with claude-local; keep it while that is still installed
[ -e "$HOME/.local/bin/claude-local" ] || rm -f "$HOME/.config/kebin/aibox.env"
rmdir "$HOME/.config/kebin" 2>/dev/null || true
echo "removed codex-local, its settings and history"

say "2/2  Codex itself"
if [ "$ALL" = 1 ]; then
  rm -f "$HOME/.local/bin/codex" "$HOME/.local/bin/codex-code-mode-host"
  command -v npm >/dev/null 2>&1 && npm ls -g @openai/codex >/dev/null 2>&1 && npm uninstall -g @openai/codex >/dev/null 2>&1 || true
  command -v brew >/dev/null 2>&1 && brew list --cask codex >/dev/null 2>&1 && brew uninstall --cask codex >/dev/null 2>&1 || true
  if command -v codex >/dev/null 2>&1; then echo "Codex is still at $(command -v codex); remove that by hand"; else echo "Codex removed (your ~/.codex settings were kept)"; fi
else
  echo "left installed. Run again with --all to remove Codex too (that also removes your normal 'codex')."
fi
say "done"
