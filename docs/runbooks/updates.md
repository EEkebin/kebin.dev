# Updates

Everything container-based updates itself once a week, early Sunday morning. Nothing updates daily on purpose: a weekly window is enough to stay current and keeps breakage to one predictable time.

| Where | Unit | When | What it does |
|---|---|---|---|
| media VM | `media-update.timer` → `/srv/media/update.sh` | Sun 04:30 | pulls every image in `compose.yml`, recreates only containers whose image changed, prunes old images. Log: `/var/log/media-update.log` |
| ai VM (user units) | `ai-update.timer` → `~/.config/ai-update.sh` | Sun 04:45 | `podman auto-update` for Quadlets with `AutoUpdate=registry` (searxng, mcp-searxng, tinyauth), then `opencode upgrade` and a web UI restart if the version changed |
| web VM | nothing automatic | | nginx comes from the nginx.org apt repo, `apt upgrade` by hand. Certificates renew via acme.sh's own cron. |

## What is held back and why

- **Jellyfin** floats on `latest`, but `update.sh` refuses to cross a major version (`MAJOR_GUARD`). Plugins are built per major (JellyBridge, Local Intros, File Transformation). When the log says a major was skipped: check the plugin catalog inside Jellyfin for builds against the new major, then run the command the log prints.
- **Nextcloud** is pinned to a major tag (`nextcloud:34-apache`). Nextcloud refuses to skip majors, so bump the tag one major at a time in `compose.yml`, run `update.sh`, open cloud.kebin.dev and let it finish its upgrade, then update the apps from its admin page.
- **Postgres** (`postgres:17-alpine`) and **Redis** (`redis:7-alpine`) are pinned to majors; a Postgres major needs a dump/restore, do not float it.
- **Recyclarr** (`:8`) and **Tinyauth** (`:v5`) are pinned to majors and move within them.
- **llama.cpp, ComfyUI, the models, the NVIDIA driver** on the ai VM are never touched automatically. llama.cpp is a custom CUDA build for three GPU generations; ComfyUI pins torch `cu126`. Update those by hand following `infra/ai/README.md`.

## By hand

```
# media VM: see what would change, then do it
sudo /srv/media/update.sh --dry-run
sudo systemctl start media-update.service && sudo tail -20 /var/log/media-update.log

# ai VM
systemctl --user start ai-update.service && journalctl --user -u ai-update -n 30 --no-pager
```

Config, databases, plugins, users and watch history live in the config volumes under `/srv/media/config`, not in the images. An update swaps the program underneath and nothing else. A container that fails to come back after an update: `podman-compose logs <name>`, and `podman-compose up -d --force-recreate --no-deps <name>` after fixing the cause.
