#!/bin/bash
# First-time setup of the media stack on the media VM. Idempotent: safe to re-run.
# Prereqs (see infra/media/README.md): podman + podman-compose, NVIDIA driver + nvidia-ctk CDI, NFS mounted at /mnt/storage.
# Usage (as root):  ./bootstrap.sh [--dry-run]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DEST=/srv/media
MEDIA=/mnt/storage/Media
DRY=${1:-}
run() { if [ "$DRY" = "--dry-run" ]; then echo "+ $*"; else "$@"; fi; }
gen() { openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 20; }

echo "== preflight"
mountpoint -q /mnt/storage || { echo "NFS share not mounted at /mnt/storage"; exit 1; }
command -v podman-compose >/dev/null || { echo "podman-compose missing"; exit 1; }
nvidia-ctk cdi list 2>/dev/null | grep -q nvidia.com/gpu || echo "warning: no CDI GPU spec found (nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml)"

echo "== folders on the share (only new ones are created; nothing existing is touched)"
for d in Downloads/incomplete Downloads/movies Downloads/tv Downloads/music Intros; do run sudo -u '#1000' mkdir -p "$MEDIA/$d"; done

echo "== app tree on local disk"
for d in jellyfin seerr prowlarr sonarr radarr lidarr bazarr recyclarr qbittorrent tdarr/server tdarr/configs tdarr/logs navidrome filebrowser nextcloud/db nextcloud/html; do run mkdir -p "$DEST/config/$d"; done
run mkdir -p "$DEST/cache/jellyfin" "$DEST/cache/tdarr" "$DEST/jellybridge"
run install -m 644 "$HERE/compose.yml" "$DEST/compose.yml"
run install -m 750 "$HERE/scripts/jellybridge-prune.py" "$DEST/jellybridge-prune.py"

echo "== secrets (generated once, kept forever)"
if [ ! -f "$DEST/.env" ]; then
  if [ "$DRY" = "--dry-run" ]; then echo "+ generate $DEST/.env"; else
    {
      for k in NC_DB_PASSWORD NC_ADMIN_PASSWORD FB_ADMIN_PASSWORD QBT_PASSWORD JF_ADMIN_PASSWORD ND_ADMIN_PASSWORD ARR_PASSWORD; do echo "$k=$(gen)"; done
      echo "JF_ADMIN_USER=admin"
    } > "$DEST/.env"
    chmod 600 "$DEST/.env"
  fi
else echo "keeping existing $DEST/.env"; fi

echo "== config templates"
if [ "$DRY" != "--dry-run" ]; then
  . "$DEST/.env"
  sed "s/__FB_ADMIN_PASSWORD__/$FB_ADMIN_PASSWORD/; s/adminUsername: .*/adminUsername: ${JF_ADMIN_USER:-admin}/" \
    "$HERE/config/filebrowser/config.yaml.tmpl" > "$DEST/config/filebrowser/config.yaml"
  chmod 600 "$DEST/config/filebrowser/config.yaml"
else echo "+ render filebrowser config.yaml"; fi
# recyclarr templates need the *arr API keys, which only exist after first boot: rendered by scripts/wire.sh

echo "== systemd"
run install -m 644 "$HERE/systemd/jellybridge-prune.service" "$HERE/systemd/jellybridge-prune.timer" /etc/systemd/system/
run mkdir -p /etc/systemd/system/podman-restart.service.d
run install -m 644 "$HERE/systemd/podman-restart.service.d/wait-for-storage.conf" /etc/systemd/system/podman-restart.service.d/
run systemctl daemon-reload
run systemctl enable --now podman-restart.service
run systemctl enable --now jellybridge-prune.timer

echo "== ownership"
run chown -R 1000:1000 "$DEST/config" "$DEST/cache" "$DEST/jellybridge"

echo "== containers"
if [ "$DRY" = "--dry-run" ]; then echo "+ podman-compose -f $DEST/compose.yml up -d"; else
  cd "$DEST" && podman-compose up -d
  echo "waiting for the apps to create their config files..."; sleep 30
  podman ps --format '{{.Names}} {{.Status}}' | sort
fi

cat <<EOF

Next:
  1. $HERE/scripts/wire.sh        connect the apps to each other (root folders, download client, indexer sync, Jellyfin libraries, Seerr, Bazarr, Recyclarr)
  2. add indexers in Prowlarr, then tag any Cloudflare-protected ones with 'flaresolverr'
  3. logins are in $DEST/.env (user: admin). Run scripts/wire.sh --credentials to print them.
EOF
