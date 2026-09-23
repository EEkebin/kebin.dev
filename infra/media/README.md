# Media VM (10.0.10.30)

Ubuntu 26.04, 8 vCPU, 15 GB RAM, Tesla P100 16 GB passed through. Rootful Podman with podman-compose. All containers run as uid/gid 1000, which is what owns every file on the NAS.

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
| FileBrowser Quantum | 8090 | files.kebin.dev |
| Nextcloud | 8081 | cloud.kebin.dev |

## Day to day

- Restart one service: `cd /srv/media && podman-compose up -d <name>`. Never run `podman-compose up -d` without a name, it recreates every container.
- Update images: `podman-compose pull <name> && podman-compose up -d <name>`.
- Podman needs fully qualified image names (`docker.io/...`). FileBrowser needs the `ip_unprivileged_port_start=0` sysctl in the compose file to bind port 80 as uid 1000.
- Jellyfin hardware settings live in `config/jellyfin/encoding.xml`; the REST endpoint rejects them on Jellyfin 12. `wire.sh` handles it.
