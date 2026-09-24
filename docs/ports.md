# Ports and names

| Public name | Backend | Notes |
|---|---|---|
| kebin.dev | web VM, `/var/www/kebin.dev` + `127.0.0.1:8765` for `/api/status` | homepage; sections at `/media/`, `/media/arr/`, `/ai/`, `/system/` |
| stream.kebin.dev | 10.0.10.30:8096 | Jellyfin, WebSocket |
| seerr.kebin.dev | 10.0.10.30:5055 | Seerr |
| sonarr.kebin.dev | 10.0.10.30:8989 | admin, behind Tinyauth, then the app's own login |
| radarr.kebin.dev | 10.0.10.30:7878 | admin, behind Tinyauth, then the app's own login |
| lidarr.kebin.dev | 10.0.10.30:8686 | admin, behind Tinyauth, then the app's own login |
| prowlarr.kebin.dev | 10.0.10.30:9696 | admin, behind Tinyauth, then the app's own login |
| bazarr.kebin.dev | 10.0.10.30:6767 | admin, behind Tinyauth, then the app's own login |
| qbittorrent.kebin.dev | 10.0.10.30:8080 | admin, behind Tinyauth, peer port 6881 tcp/udp is not forwarded |
| tdarr.kebin.dev | 10.0.10.30:8265 | admin, behind Tinyauth (Tdarr has no login of its own) |
| music.kebin.dev | 10.0.10.30:4533 | Navidrome |
| files.kebin.dev | 10.0.10.30:8090 | FileBrowser Quantum, uploads unlimited |
| cloud.kebin.dev | 10.0.10.30:8081 | Nextcloud, uploads unlimited, well-known redirects for CalDAV/CardDAV |
| auth.kebin.dev | 10.0.10.100:3000 | Tinyauth login page |
| code.kebin.dev | 10.0.10.100:4096 | OpenCode web, behind Tinyauth |
| comfy.kebin.dev | 10.0.10.100:8188 | ComfyUI, behind Tinyauth |
| pve.kebin.dev | https://10.0.0.200:8006 | Proxmox UI, behind Tinyauth, self-signed upstream |
| ai.kebin.dev | 10.0.10.100:8080 | llama-swap: `/v1/` needs the bearer key (`$ai_key_ok` from `/etc/nginx/secrets/ai-key-map.conf`), the dashboard at `/ui/` takes the key or a Tinyauth login |
| search.kebin.dev | 10.0.10.100:8888 and :8899 | SearXNG's page behind Tinyauth; `/mcp` and `/health` go to mcp-searxng with the same bearer key as ai.kebin.dev |
| kebin.dev/cli/ | static | OpenCode CLI installers; page behind Tinyauth with the API key filled in, scripts public |
| vr.kebin.dev | 10.0.10.30:8000 | HLS for VRChat players, per-share tokens, no Tinyauth on purpose |

Internal only on the ai VM: SearXNG 10.0.10.100:8888 (LAN), mcp-searxng 10.0.10.100:8899 (LAN, used by OpenCode on the VM and by nginx for search.kebin.dev).

Router forwards: 80/tcp, 443/tcp, 443/udp to 10.0.10.20. Nothing else.

Container-to-container names (inside the podman network): `jellyfin`, `seerr`, `sonarr`, `radarr`, `lidarr`, `prowlarr`, `bazarr`, `qbittorrent`, `flaresolverr:8191`, `nextcloud-db`, `nextcloud-redis`.
