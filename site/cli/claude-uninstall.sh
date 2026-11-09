#!/usr/bin/env bash
# Removes what claude-install.sh set up. Your normal `claude` settings in ~/.claude are never touched.
#   curl -fsSL https://kebin.dev/cli/claude-uninstall.sh | bash             # remove claude-local and its settings/history
#   curl -fsSL https://kebin.dev/cli/claude-uninstall.sh | bash -s -- --all  # also remove Claude Code itself
set -euo pipefail
ALL=0; [ "${1:-}" = "--all" ] && ALL=1
say() { printf '\033[1;33m%s\033[0m\n' "$*"; }

say "1/2  claude-local"
rm -f "$HOME/.local/bin/claude-local"
rm -rf "$HOME/.claude-local"
# the key file is shared with codex-local; keep it while that is still installed
[ -e "$HOME/.local/bin/codex-local" ] || rm -f "$HOME/.config/kebin/aibox.env"
rmdir "$HOME/.config/kebin" 2>/dev/null || true
echo "removed claude-local, its settings and history"

say "2/2  Claude Code itself"
if [ "$ALL" = 1 ]; then
  rm -f "$HOME/.local/bin/claude"
  rm -rf "$HOME/.local/share/claude"
  command -v npm >/dev/null 2>&1 && npm ls -g @anthropic-ai/claude-code >/dev/null 2>&1 && npm uninstall -g @anthropic-ai/claude-code >/dev/null 2>&1 || true
  command -v brew >/dev/null 2>&1 && brew list --cask claude-code >/dev/null 2>&1 && brew uninstall --cask claude-code >/dev/null 2>&1 || true
  echo "Claude Code removed (your ~/.claude settings were kept)"
else
  echo "left installed. Run again with --all to remove Claude Code too (that also removes your normal 'claude')."
fi
say "done"
