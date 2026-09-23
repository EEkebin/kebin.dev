#!/bin/bash
# Deploy the homepage and nginx config from this repo checkout onto the web VM.
# Usage (as root on the web VM):  /srv/kebin.dev/infra/web/deploy.sh [--no-pull]
set -euo pipefail
REPO=/srv/kebin.dev
WEBROOT=/var/www/kebin.dev

cd "$REPO"
[ "${1:-}" = "--no-pull" ] || git pull --ff-only

# site
mkdir -p "$WEBROOT"
rsync -a --delete "$REPO/site/" "$WEBROOT/"
chown -R nginx:nginx "$WEBROOT"

# nginx: snippets + every server block in the repo
install -m 644 "$REPO"/infra/web/nginx/snippets/*.conf /etc/nginx/snippets/
install -m 644 "$REPO"/infra/web/nginx/conf.d/*.conf   /etc/nginx/conf.d/
nginx -t
systemctl reload nginx

# status endpoint
install -m 644 "$REPO/infra/web/status/kebin-status.service" /etc/systemd/system/kebin-status.service
systemctl daemon-reload
systemctl enable --now kebin-status.service >/dev/null
systemctl restart kebin-status.service

echo "deployed $(git rev-parse --short HEAD)"
