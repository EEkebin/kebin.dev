#!/bin/bash
# Recreate containers that look "Up" but have lost their conmon supervisor (after a power loss, or after
# anything killed conmon: an ill-behaved systemd unit, an OOM kill). `podman exec` still works on such
# containers, so the only reliable test is whether the conmon pid is alive. Run as root:
#   /srv/media/revive.sh            recreate what is dead
#   /srv/media/revive.sh --check    only report
set -uo pipefail
cd /srv/media || exit 1
CHECK=0; [ "${1:-}" = "--check" ] && CHECK=1
dead=0
for c in $(podman ps -a --format '{{.Names}}'); do
  st=$(podman inspect --format '{{.State.Status}}' "$c" 2>/dev/null)
  pid=$(podman inspect --format '{{.State.ConmonPid}}' "$c" 2>/dev/null)
  if [ "$st" != running ] || [ -z "$pid" ] || [ "$pid" = 0 ] || ! kill -0 "$pid" 2>/dev/null; then
    dead=$((dead+1))
    if [ "$CHECK" = 1 ]; then echo "$c: status=$st conmon=${pid:-none} (dead)"; continue; fi
    echo "$c: status=$st conmon=${pid:-none} dead, recreating"
    podman rm -f "$c" >/dev/null 2>&1
    podman-compose up -d --no-deps "$c" >/dev/null 2>&1 && echo "  $c up" || echo "  $c FAILED, see podman-compose logs $c"
  fi
done
echo "$dead container(s) were dead"
