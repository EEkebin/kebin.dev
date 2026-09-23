# Runbook: watching the Jellyfin library in VRChat

`vr.kebin.dev` is an HLS proxy ([jellyfin-vrc-stream](https://github.com/C9Glax/jellyfin-vrc-stream), container `vrc-stream` on the media VM). Jellyfin transcodes a title once on the P100, the proxy caches the segments, and every VRChat viewer pulls from the cache. Access is by per-title share token, not by login, because VRChat video players fetch URLs anonymously.

## Sharing a title

1. Open the movie or episode in Jellyfin (stream.kebin.dev) as an admin.
2. Click **VR Share Link** (added by the "VRC Share" plugin). It creates a link like `https://vr.kebin.dev/vod.m3u8?m=<id>&token=<token>&profile=vrchat` valid for 24 hours.
3. Paste the link into the world's video player. For public instances the world must allow the `vr.kebin.dev` domain or viewers must enable "Allow Untrusted URLs"; in friends instances the toggle alone is enough.

## Quality profiles

Bandwidth is the limit: the connection has about 39 Mbit/s upload and each viewer streams separately.

| Profile | Output | Viewers that fit | When |
|---|---|---|---|
| `vrchat` (default) | H.264 6 Mbit/s cap, AAC stereo; Jellyfin picks 720p at this bitrate, measured about 4.7 Mbit/s | about 6 | small groups |
| `vrchat-720` | H.264 3 Mbit/s cap, 720p | about 10 | bigger rooms |
| built-ins `potato`, `low`, `medium`, `high` | 2 to 40 Mbit/s | | `high` and above will not work over this uplink |

Change the default in Jellyfin → Dashboard → Plugins → VRC Share → Default Quality Profile. Profiles are managed through the proxy's `/profiles` API with the admin key (`VRC_STREAM_KEY` in `/srv/media/.env`).

## Player notes

- Use HLS (this proxy) and HTTPS for Quest and Android; plain MP4 URLs and HTTP do not play there.
- If a world's player has both Unity and AVPro modes, Unity is more forgiving with HLS.
- First play of a title takes a few seconds while the first segments encode; later viewers start instantly from cache.
- Subtitles are burned in when a subtitle stream is selected in the share; audio defaults to the first track. Multi-language files: pick the audio index in the share dialog.

## Operating it

- Cache lives at `/srv/media/cache/vrc-stream`, capped at 20 GB, idle streams cleared after 15 minutes.
- Status: `curl -H "X-Admin-Key: $VRC_STREAM_KEY" http://127.0.0.1:8000/streams` on the media VM.
- Revoke a link: `DELETE /share/<token>` with the admin key. List: `GET /shares`.
- The proxy's Jellyfin API key is named `vrc-stream` in Jellyfin → Dashboard → API Keys.
