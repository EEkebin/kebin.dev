# Ports and names

| Public name | Backend | Notes |
|---|---|---|
| kebin.dev | web VM, `/var/www/kebin.dev` + `127.0.0.1:8765` for `/api/status` | homepage |
| stream.kebin.dev | 10.0.10.30:8096 | Jellyfin, WebSocket |
| seerr.kebin.dev | 10.0.10.30:5055 | Seerr |
| sonarr.kebin.dev | 10.0.10.30:8989 | admin |
| radarr.kebin.dev | 10.0.10.30:7878 | admin |
| lidarr.kebin.dev | 10.0.10.30:8686 | admin |
| prowlarr.kebin.dev | 10.0.10.30:9696 | admin |
| bazarr.kebin.dev | 10.0.10.30:6767 | admin |
| qbittorrent.kebin.dev | 10.0.10.30:8080 | admin, peer port 6881 tcp/udp is not forwarded |
| tdarr.kebin.dev | 10.0.10.30:8265 | admin, no login by default |
| music.kebin.dev | 10.0.10.30:4533 | Navidrome |
| files.kebin.dev | 10.0.10.30:8090 | FileBrowser Quantum, uploads unlimited |
| cloud.kebin.dev | 10.0.10.30:8081 | Nextcloud, uploads unlimited, well-known redirects for CalDAV/CardDAV |
| auth.kebin.dev | 10.0.10.100:3000 | Tinyauth login page |
| code.kebin.dev | 10.0.10.100:4096 | OpenCode web, behind Tinyauth |
| comfy.kebin.dev | 10.0.10.100:8188 | ComfyUI, behind Tinyauth |
| pve.kebin.dev | https://10.0.0.200:8006 | Proxmox UI, behind Tinyauth, self-signed upstream |
| ai.kebin.dev | 10.0.10.100:8080 | model API (llama-swap), bearer key from `/etc/nginx/secrets/ai-key` on the web VM |
| kebin.dev/cli/ | static | OpenCode CLI installers (install.sh, install.ps1) |
| vr.kebin.dev | 10.0.10.30:8000 | HLS for VRChat players, per-share tokens, no Tinyauth on purpose |

Router forwards: 80/tcp, 443/tcp, 443/udp to 10.0.10.20. Nothing else.

Container-to-container names (inside the podman network): `jellyfin`, `seerr`, `sonarr`, `radarr`, `lidarr`, `prowlarr`, `bazarr`, `qbittorrent`, `flaresolverr:8191`, `nextcloud-db`, `nextcloud-redis`.
