#!/bin/bash
# One feed (RSS) check per day for Sonarr, Radarr and Lidarr, run by media-rss-daily.timer.
# The apps' own "RSS Sync Interval" only allows 10-120 minutes or 0 (off). It is set to 0 on purpose:
# polling every 15-30 minutes got the home IPv4 banned by an indexer (2026-10-01). This asks each app
# for a single RssSync instead, so airing shows and unreleased movies still get picked up, once a day.
set -uo pipefail
key() { grep -oP '(?<=<ApiKey>)[^<]+' "/srv/media/config/$1/config.xml"; }
run() {  # name port api-version
  code=$(curl -s -m 30 -o /dev/null -w '%{http_code}' -X POST -H "X-Api-Key: $(key "$1")" -H 'Content-Type: application/json' \
         -d '{"name":"RssSync"}' "http://127.0.0.1:$2/api/$3/command")
  echo "$(date -Is) $1 RssSync -> HTTP $code"
}
run sonarr 8989 v3
sleep 120
run radarr 7878 v3
sleep 120
run lidarr 8686 v1
