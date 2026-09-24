#!/bin/bash
# Weekly image update for the media stack (run by media-update.timer, or by hand as root).
#   /srv/media/update.sh            update whatever changed
#   /srv/media/update.sh --dry-run  only report what would change
#
# Pulls every image named in compose.yml, recreates only the containers whose image actually changed,
# and refuses to move MAJOR_GUARD services across a major version on their own (Jellyfin plugins are
# built per major; do that one by hand after checking the plugin catalog). Nextcloud is pinned to a
# major tag in compose.yml for the same reason. Old images are pruned at the end.
#
# Each recreate runs inside its own transient systemd scope (systemd-run --scope). Without that, the
# containers' conmon supervisors land in media-update.service's cgroup and get killed when the oneshot
# unit finishes, which leaves containers "Up" but dead. The unit writes stdout to /var/log/media-update.log.
set -uo pipefail
cd /srv/media || exit 1
DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1
MAJOR_GUARD="jellyfin"
echo "=== $(date -Is) media update$([ "$DRY" = 1 ] && echo ' (dry run)')"

major() { echo "${1:-0}" | grep -oE '^[0-9]+' || echo 0; }
ver_of_container() { podman inspect --format '{{index .Config.Labels "org.opencontainers.image.version"}}' "$1" 2>/dev/null; }
ver_of_image() {
  local v; v=$(podman image inspect --format '{{index .Labels "org.opencontainers.image.version"}}' "$1" 2>/dev/null)
  [ -n "$v" ] && echo "$v" || podman image inspect --format '{{.Id}}' "$1" 2>/dev/null | cut -c1-12
}
recreate() {
  if command -v systemd-run >/dev/null 2>&1; then
    systemd-run --quiet --scope --collect --unit "media-recreate-$1-$RANDOM" podman-compose up -d --force-recreate --no-deps "$1"
  else
    podman-compose up -d --force-recreate --no-deps "$1"
  fi
}

changed=0; skipped=0
while read -r svc image; do
  old=$(podman inspect --format '{{.Image}}' "$svc" 2>/dev/null || true)
  if ! podman pull -q "$image" >/dev/null 2>&1; then echo "  $svc: pull failed for $image, left as is"; continue; fi
  new=$(podman image inspect --format '{{.Id}}' "$image" 2>/dev/null || true)
  [ -n "$old" ] && [ "$old" = "$new" ] && continue
  if [[ " $MAJOR_GUARD " == *" $svc "* ]]; then
    ov=$(ver_of_container "$svc"); nv=$(ver_of_image "$image")
    if [ "$(major "$ov")" != "$(major "$nv")" ]; then
      echo "  $svc: NOT updated, major version change $ov -> $nv. Check plugins, then: podman-compose up -d --force-recreate --no-deps $svc"
      skipped=$((skipped+1)); continue
    fi
  fi
  if [ "$DRY" = 1 ]; then echo "  $svc: would update ($(ver_of_container "$svc" || echo '?') -> $(ver_of_image "$image"))"; changed=$((changed+1)); continue; fi
  if recreate "$svc" >/dev/null 2>&1; then
    echo "  $svc: updated -> $(ver_of_image "$image")"; changed=$((changed+1))
  else
    echo "  $svc: recreate FAILED, check 'podman-compose logs $svc'"
  fi
done < <(python3 -c '
import yaml
c = yaml.safe_load(open("compose.yml"))
for name, svc in c["services"].items():
    print(name, svc["image"])
')

[ "$DRY" = 1 ] || podman image prune -f >/dev/null 2>&1
echo "done: $changed updated, $skipped held back"
