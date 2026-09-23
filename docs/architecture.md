# Architecture

## Hosts

| Host | Address | Role |
|---|---|---|
| router | 76.x WAN | forwards 80/tcp, 443/tcp, 443/udp to the web VM |
| web | 10.0.10.20 | nginx 1.30 with HTTP/3, wildcard TLS, homepage, status endpoint |
| media | 10.0.10.30 | Podman stack, Tesla P100 for NVENC/NVDEC |
| nas | 10.0.10.10 | NFS export `/srv/tank/storage` (16 TB ZFS) |

DNS is at Porkbun: one A record per subdomain pointing at the WAN IP. The WAN IP is residential and can change; there is deliberately no dynamic-DNS updater, records are updated by hand.

## Request to playback

```
user ── Seerr (request) ──▶ Radarr / Sonarr
                              │ search via Prowlarr (indexers, FlareSolverr for Cloudflare ones)
                              │ pick release by TRaSH profile (Recyclarr keeps profiles current)
                              ▼
                          qBittorrent ──▶ /data/Downloads/<category>
                              │ on completion: hardlink + rename
                              ▼
                     /data/Movies | /data/TV | /data/Music
                              │ arr → Jellyfin "library updated" hook
                              ▼
                          Jellyfin (stream.kebin.dev)  ◀── Bazarr adds subtitles
```

Navidrome indexes `Media/Music` hourly. FileBrowser and Nextcloud see the whole share (Nextcloud read-only via External Storage).

## Discover inside Jellyfin

JellyBridge (Jellyfin plugin) pulls streaming-catalog titles from Seerr into a "Discover" library made of placeholder clips. Favoriting one sends a Seerr request. Jellyfin 12 ignores `.ignore` files, so a systemd timer (`jellybridge-prune`) removes titles already owned. See the runbook.

## Transcoding

Jellyfin transcodes on the fly with NVENC for anything a client cannot direct play. Tdarr holds a "Web friendly MP4" flow that remuxes MKV remuxes to MP4 with an AAC 5.1 track added, video untouched, all audio languages kept. Its library is scoped narrowly on purpose.

## What is public

Everything under `*.kebin.dev` is reachable from the internet behind each app's own login. The homepage links only Stream, Seerr, Music, Files and Cloud. Admin UIs are not linked but are reachable by name.
