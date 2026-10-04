# Runbook: Prowlarr indexers

All indexers are public, added in Prowlarr (prowlarr.kebin.dev) and pushed to Sonarr/Radarr/Lidarr by full sync. Never add indexers inside Sonarr or Radarr directly; the next sync would remove them.

| Indexer | Route | For | Notes |
|---|---|---|---|
| 1337x | FlareSolverr | movies, TV | base URL is the mirror `https://1337x.st/`. `1337x.to` banned the home IP (Cloudflare error 1006, 2026-10-04); mirrors only show a normal challenge |
| YTS | direct | movies | small encodes |
| The Pirate Bay | direct | movies, TV | "Top100" set to Movies/TV, otherwise Radarr rejects it on sync ("No results in configured categories") |
| LimeTorrents | direct | TV | sorted by seeders. Its keywordless feed is all category "Other", so Radarr refuses it; it stays TV-only |
| Knaben | direct | movies, TV | meta-indexer over many public sites |
| EZTV | FlareSolverr | TV | recent feed and title/season/episode search work; ID-only search returns nothing |
| Nyaa.si | direct | anime | category locked to **Anime - English-translated**, so results carry English subs or dub; Sonarr/Radarr title compatibility options on |
| SubsPlease | direct | anime | English-subbed simulcast releases, consistent naming |
| Anime Tosho | direct | anime | mirror/aggregator of English-translated releases |

Anime in Sonarr: set the series type to **Anime** when adding a show. Sonarr then searches the anime category (5070) with absolute episode numbers, plus the standard SxxEyy form (Prowlarr's "Sync Anime Standard Format Search" is on).

## How often the apps poll

Once a day. The built-in "RSS Sync Interval" in Sonarr, Radarr and Lidarr is set to **0 (off)**; it only accepts 10 to 120 minutes, and at the 15 and 30 minute defaults three apps sent about 930 page loads a day to a single indexer, which got the home IPv4 address banned by 1337x.to on 2026-10-01 (IPv6 was unaffected, which is why a desktop browser still reached it). `media-rss-daily.timer` (05:00) runs `/srv/media/rss-daily.sh`, which asks each app for one `RssSync`; log in `/var/log/media-rss-daily.log`. Requests from Seerr and manual searches are unaffected: they search immediately.

Do not raise the built-in interval again. To check more often, change `OnCalendar` in the timer.

## Adding one

Prowlarr → Indexers → Add. Leave tags empty first; if the test says Cloudflare, add the `flaresolverr` tag (the FlareSolverr proxy is bound to that tag). If the first base URL fails, pick another from the dropdown. After saving, Prowlarr syncs it to the apps within a minute; an app refuses an indexer whose test feed has no results in that app's categories.

## When an indexer goes red

`System → Status` in Prowlarr shows it with a back-off time. Typical causes and fixes:

- Cloudflare challenge: add the `flaresolverr` tag.
- `error code: 1006` or FlareSolverr says "your IP is banned": switch the base URL to a mirror.
- Site moved: update Prowlarr (weekly updater does it) or choose a new base URL.

Check a search by hand from the media VM: `curl "http://127.0.0.1:9696/<indexer id>/api?t=tvsearch&q=<title>&season=1&ep=1&apikey=<prowlarr key>"`.
