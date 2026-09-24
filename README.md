# kebin.dev

Homepage and the full self-hosted media stack behind it, as code.

```
site/          the homepage served at https://kebin.dev (static HTML + htmx status), sections /media/, /media/arr/, /ai/, /system/
infra/web/     nginx reverse proxy with HTTP/3, TLS, and the tiny status endpoint
infra/media/   podman-compose stack: Jellyfin, Seerr, *arr, qBittorrent, Tdarr, Navidrome, FileBrowser, Nextcloud
infra/ai/      llama-swap model router, OpenCode web, ComfyUI, Tinyauth on the GPU VM
site/cli/      one-line installers that set up the OpenCode CLI against ai.kebin.dev
docs/          architecture, port map, runbooks
```

## How it fits together

```
 internet ──443/80──▶ web VM 10.0.10.20 (nginx, HTTP/3, wildcard cert)
                        │  *.kebin.dev ─▶ reverse proxy
                        ▼
                     media VM 10.0.10.30 (podman, Tesla P100)
                        │  containers read/write
                        ▼
                     NAS 10.0.10.10  nfs:/srv/tank/storage ─▶ /mnt/storage
```

Requests flow Seerr → Radarr/Sonarr → Prowlarr indexers → qBittorrent → hardlink into `Media/Movies|TV` → Jellyfin rescans. See [docs/architecture.md](docs/architecture.md).

## Deploy the homepage

On the web VM, once: `git clone https://github.com/eekebin/kebin.dev /srv/kebin.dev && /srv/kebin.dev/infra/web/deploy.sh --no-pull`.
After that, every update is `sudo /srv/kebin.dev/infra/web/deploy.sh` (pulls, syncs `site/`, installs nginx configs, restarts the status service).

## Bring up the media stack

`infra/media/README.md` covers the host prerequisites (driver, container toolkit, NFS). Then:

```
sudo infra/media/bootstrap.sh        # folders, generated secrets, containers
sudo infra/media/scripts/wire.sh     # connect the apps to each other
sudo infra/media/scripts/wire.sh --credentials
```

## Secrets

Nothing sensitive lives in this repo. `bootstrap.sh` generates `/srv/media/.env` on first run; the *arr API keys are created by the apps themselves. `.gitignore` blocks `.env`, `CREDENTIALS.md`, databases and runtime config directories. Where each secret lives on the web VM is in [infra/web/README.md](infra/web/README.md). Weekly automatic updates: [docs/runbooks/updates.md](docs/runbooks/updates.md).
