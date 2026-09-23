# Runbook: Discover library (JellyBridge)

JellyBridge is a Jellyfin plugin. It reads Seerr's discover pages for the chosen streaming networks (US region: Netflix, Prime Video, Disney+, Hulu, HBO Max, Peacock) and writes one folder per title into `/srv/media/jellybridge`, mounted in the container at `/jellybridge`. Each folder holds an `.nfo`, `metadata.json` and a short placeholder clip so Jellyfin indexes it as a movie or series. Favoriting an item sends a Seerr request.

Plugin settings: Dashboard → Plugins → JellyBridge. Seerr URL `http://seerr:5055`, API key from Seerr → Settings → General, library directory `/jellybridge`. The plugin syncs daily.

## Known problem and the fix in place

Jellyfin 10.11 and 12 no longer honor `.ignore` files (jellyfin issue #14502), so the plugin's "hide titles you already own" produces empty folder tiles. The option is turned off and `scripts/jellybridge-prune.py`, run by `jellybridge-prune.timer` four times a day, deletes Discover entries whose TMDB id or name+year matches something in Movies or TV. It moves the folder aside before the Jellyfin delete so Jellyfin never touches real files.

## Resetting

If Discover shows bare folders or blank entries: on the plugin page click **Recycle Library**, then **Sync**, then run `systemctl start jellybridge-prune.service`. The Discover library must exist before the first sync or entries get no placeholder clip.
