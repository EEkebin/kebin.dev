# Media VM (10.0.10.30)

Ubuntu 26.04, 8 vCPU, three Tesla V100 16 GB passed through (CUDA0 SXM2, CUDA1 and CUDA2 PCIe). Rootful Podman with podman-compose. All containers run as uid/gid 1000, which is what owns every file on the NAS.

## Host prerequisites

### NVIDIA driver (Pascal needs the 580 branch; newer branches dropped the P100)

```
ubuntu-drivers install --gpgpu
apt-get install -y nvidia-utils-580-server libnvidia-encode-580-server libnvidia-decode-580-server
reboot
nvidia-smi
```

### Container toolkit + CDI (how Podman hands the GPU to containers)

```
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -sL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' > /etc/apt/sources.list.d/nvidia-container-toolkit.list
apt-get update && apt-get install -y nvidia-container-toolkit
nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml      # re-run after every driver upgrade
podman run --rm --device nvidia.com/gpu=all ubuntu nvidia-smi
```

### NFS

The NAS export must allow this subnet. Then:

```
apt-get install -y nfs-common
mkdir -p /mnt/storage
echo '10.0.10.10:/srv/tank/storage  /mnt/storage  nfs  nfsvers=4.2,_netdev,nofail,noatime  0  0' >> /etc/fstab
systemctl daemon-reload && mount -a
```

`nofail` keeps the VM booting if the NAS is down. `systemd/podman-restart.service.d/wait-for-storage.conf` makes container autostart wait for the mount.

## Layout on the host

```
/srv/media/compose.yml        from this repo
/srv/media/.env               generated secrets (never committed)
/srv/media/config/<app>/      each app's state
/srv/media/cache/{jellyfin,tdarr}   transcode scratch on local disk
/srv/media/jellybridge/       JellyBridge Discover library (placeholder files)
/mnt/storage/Media/           Movies, TV, Music, Books, Downloads/{incomplete,movies,tv,music}, Intros
```

Every *arr container and qBittorrent mount `/mnt/storage/Media` at `/data`, so paths match across apps and imports are hardlinks, not copies.

## Ports (host)

| Service | Port | Public name |
|---|---|---|
| Jellyfin | 8096 | stream.kebin.dev |
| Seerr | 5055 | seerr.kebin.dev |
| Sonarr | 8989 | sonarr.kebin.dev |
| Radarr | 7878 | radarr.kebin.dev |
| Lidarr | 8686 | lidarr.kebin.dev |
| Prowlarr | 9696 | prowlarr.kebin.dev |
| Bazarr | 6767 | bazarr.kebin.dev |
| qBittorrent | 8080, 6881 | qbittorrent.kebin.dev |
| Tdarr | 8265 (UI), 8266 (server) | tdarr.kebin.dev |
| Navidrome | 4533 | music.kebin.dev |
| llama-swap (systemd, not a container) | 8086 | ai.kebin.dev, see `infra/ai/README.md` |
| ComfyUI (sandboxed: sees only its own folder) | 8188 | comfy.kebin.dev |
| FileBrowser Quantum | 8090 | files.kebin.dev |
| Nextcloud | 8081 | cloud.kebin.dev |
| Audiobookshelf | 13378 | books.kebin.dev |
| Shelfmark | 8084 | shelfmark.kebin.dev |
| aria2 + AriaNg (download portal) | 6800 (RPC), 6880 (UI), 6888 (peers) | downloads.kebin.dev |
| ia-queue (archive.org helper, host service) | 8097 | downloads.kebin.dev/ia/ |

## Day to day

- IPv6: the container network is dual-stack and the VM needs `accept-ra: true` in netplan. Details and the reason for the odd internal subnet are in `docs/runbooks/ipv6.md`.

- Restart one service: `cd /srv/media && podman-compose up -d <name>`. Never run `podman-compose up -d` without a name, it recreates every container.
- Updates run weekly on their own (`media-update.timer`, Sunday 04:30, `/srv/media/update.sh`, log in `/var/log/media-update.log`). By hand: `sudo /srv/media/update.sh --dry-run` then `sudo /srv/media/update.sh`. Jellyfin never crosses a major automatically and Nextcloud is pinned to a major tag, see `docs/runbooks/updates.md`.
- Podman needs fully qualified image names (`docker.io/...`). FileBrowser needs the `ip_unprivileged_port_start=0` sysctl in the compose file to bind port 80 as uid 1000.
- Jellyfin hardware settings live in `config/jellyfin/encoding.xml`; the REST endpoint rejects them on Jellyfin 12. `wire.sh` handles it.

## Local video models

ComfyUI on the media VM serves SDXL Base 1.0 and Lightricks LTX-Video 2B. The
`/ai/` page lists these beside the text service. The ComfyUI container sees one
16 GB V100. Its models, workflows, inputs and outputs persist in its existing
bind mount. No custom video nodes are required.

On the media VM, from `infra/media/comfyui/` with Python 3.11+:

    root=/srv/media/config/comfyui/ComfyUI
    python3 fetch-local-video.py "$root"
    python3 local-video.py "$root"

In ComfyUI, open Workflows > Local video. The text and image workflows use the
checkpoint versions specified by the installed ComfyUI templates (0.9 and
0.9.5 respectively). Video restyling uses 0.9.5. Start at 512x320 and 49 frames.
For an image shot, upload a still. For restyling, upload a short clip; the
workflow decodes the input before selecting the first 49 frames. A larger
SplitSigmas step retains more of the source. These workflows output silent
clips. Assemble shots and audio in a video editor.
