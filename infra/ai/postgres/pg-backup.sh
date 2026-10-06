#!/bin/bash
# Dump every database (pg_dumpall) to ~/.local/share/postgres-backups, keep the last 7.
# Run daily by pg-backup.timer and once more by ai-update.sh right before container images are updated,
# so a major-version upgrade can always be undone by restoring the last dump:
#   zcat <file> | podman exec -i postgres psql -U admin -d postgres
set -uo pipefail
D="$HOME/.local/share/postgres-backups"; mkdir -p "$D"
f="$D/pgdumpall-$(date +%Y%m%d-%H%M%S).sql.gz"
if podman exec postgres pg_dumpall -U admin --clean --if-exists | gzip -6 > "$f.tmp" && [ -s "$f.tmp" ]; then
  mv "$f.tmp" "$f"; echo "$(date -Is) dump ok $(du -h "$f" | cut -f1) $(basename "$f")"
else
  rm -f "$f.tmp"; echo "$(date -Is) dump FAILED"; exit 1
fi
ls -1t "$D"/pgdumpall-*.sql.gz 2>/dev/null | tail -n +8 | xargs -r rm -f
