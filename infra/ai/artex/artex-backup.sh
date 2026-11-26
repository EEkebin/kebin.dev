#!/bin/bash
# Daily ARTEX backup: DB dump (from artex-postgres) + data/ (traffic blobs, transcripts, task files)
# + jwt.key and secret.key (the dump is useless without secret.key) to ~/.local/share/artex-backups, keep the last 7.
# Restore:
#   zcat artex-<ts>.sql.gz | podman exec -i artex-postgres psql -h 127.0.0.1 -p 5433 -U artex -d artex
#   untar artex-<ts>.data.tar.gz into /srv/artex/ (same keys, same data), restart artex
set -uo pipefail
D="$HOME/.local/share/artex-backups"; mkdir -p "$D"
ts=$(date +%Y%m%d-%H%M%S)
PASS=$(cut -d= -f2 /srv/artex/.pg.env)
f="$D/artex-$ts"
if podman exec -e PGPASSWORD="$PASS" artex-postgres pg_dump -h 127.0.0.1 -p 5433 -U artex -d artex --clean --if-exists | gzip -6 > "$f.sql.gz.tmp" && [ -s "$f.sql.gz.tmp" ]; then
  mv "$f.sql.gz.tmp" "$f.sql.gz"; echo "$(date -Is) db dump ok $(du -h "$f.sql.gz" | cut -f1)"
else
  rm -f "$f.sql.gz.tmp"; echo "$(date -Is) db dump FAILED"; exit 1
fi
if tar czf "$f.data.tar.gz" -C /srv/artex data jwt.key secret.key; then
  echo "$(date -Is) data+keys ok $(du -h "$f.data.tar.gz" | cut -f1)"
else
  echo "$(date -Is) data+keys FAILED"
fi
ls -1t "$D"/artex-*.sql.gz 2>/dev/null | tail -n +8 | xargs -r rm -f
ls -1t "$D"/artex-*.data.tar.gz 2>/dev/null | tail -n +8 | xargs -r rm -f
