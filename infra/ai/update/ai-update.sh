#!/bin/bash
# Weekly update for the ai VM, run by ai-update.timer as the `user` account.
#   containers with AutoUpdate=registry in their Quadlet (searxng, mcp-searxng, tinyauth): podman auto-update
#   OpenCode: `opencode upgrade`, then restart the web UI if the version changed
# Not touched on purpose: llama.cpp (custom CUDA build), ComfyUI (torch pins), the models themselves.
set -uo pipefail
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
OC="$HOME/.opencode/bin/opencode"
echo "=== $(date -Is) ai update"

echo "-- containers"
podman auto-update 2>&1 | grep -vE '^\s*$' | sed 's/^/  /'
podman image prune -f >/dev/null 2>&1 || true

echo "-- opencode"
before=$("$OC" --version 2>/dev/null | head -1)
"$OC" upgrade >/dev/null 2>&1 || echo "  upgrade command failed, kept $before"
after=$("$OC" --version 2>/dev/null | head -1)
if [ "$before" != "$after" ]; then
  systemctl --user restart opencode-web.service && echo "  $before -> $after, web UI restarted"
else
  echo "  $after, no change"
fi
echo "done"
