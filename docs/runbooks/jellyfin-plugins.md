# Runbook: Jellyfin plugins

Plugins live in the Jellyfin config volume (`/srv/media/config/jellyfin/data/plugins`), not in the image, so container updates keep them. They are built per Jellyfin **major**, which is why `update.sh` never crosses a major on its own (see `updates.md`).

| Plugin | Repository manifest | What it is for |
|---|---|---|
| Jellyfin Enhanced | `https://raw.githubusercontent.com/n00bcodr/jellyfin-plugins/main/manifest.json` | Seerr results and a Request button inside Jellyfin's search, request buttons and recommendations on item pages |
| JellyBridge | `https://raw.githubusercontent.com/kinggeorges12/JellyBridge/refs/heads/main/manifest.json` | the Discover library (see `discover-jellybridge.md`) |
| File Transformation | `https://www.iamparadox.dev/jellyfin/plugins/manifest.json` | lets the two plugins above modify the web UI without file permission issues |
| Local Intros | Jellyfin Stable repo | plays `kebinStream-intro.mp4` before items in Jellyfin clients |
| VRC Share | `https://raw.githubusercontent.com/C9Glax/jellyfin-vrc-stream/main/jellyfin-plugin-vrc-share/manifest.json` | "VR Share Link" button (see `vrchat-streaming.md`) |

Install or reinstall: Dashboard → Plugins → Repositories → add the manifest URL → Catalog → install → restart Jellyfin.

## Jellyfin Enhanced: Seerr search and requests

Settings (Dashboard → Plugins → Jellyfin Enhanced → Seerr):

| Setting | Value |
|---|---|
| Enabled | on |
| Seerr URL | `http://seerr:5055` (container name; the plugin calls Seerr server-side) |
| API key | Seerr → Settings → General → API Key (also in `/srv/media/config/seerr/settings.json`) |
| Show Seerr results in search | on |
| URL mapping | `https://stream.kebin.dev|https://seerr.kebin.dev` so links shown to users open the public Seerr |
| Auto-import users | on, so a new Jellyfin user gets a Seerr user and can request |

Requests are made as the Seerr user linked to the signed-in Jellyfin user. If a user sees results but no Request button, that link is missing: Seerr → Users → import Jellyfin users.

Checks (any signed-in session, `Authorization: MediaBrowser ... Token="..."`):

```
GET /JellyfinEnhanced/jellyseerr/status        -> {"active":true}
GET /JellyfinEnhanced/jellyseerr/user-status   -> {"userFound":true,"reason":"linked"}
GET /JellyfinEnhanced/jellyseerr/search?query=dune
```

Works in the web UI, the official phone apps and Jellyfin Desktop. Android TV and third-party clients do not load the modified web UI, so they show plain Jellyfin search. After installing or updating the plugin, browsers need a hard refresh to pick up the new interface.

The plugin's pre-Seerr default configuration is saved at `/srv/media/config/jellyfin/je-config.pre-seerr.bak.json`.
