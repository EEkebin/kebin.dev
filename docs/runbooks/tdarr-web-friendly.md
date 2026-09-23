# Runbook: Tdarr "Web friendly MP4" flow

Purpose: make Blu-ray remuxes (MKV, DTS-HD/TrueHD audio) seek instantly in browsers by remuxing to MP4 with an AAC track, without re-encoding video.

Flow, in order: input → skip if already `.mp4` → set container mp4 → ensure AAC 5.1 English stream (encoded from the best existing track) → drop lossless audio MP4 cannot carry (dts, truehd, flac, pcm) → drop embedded subtitles (Bazarr provides external ones) → drop data streams → reorder so AAC is first → `-movflags +faststart` → execute → replace original.

All audio languages are kept on purpose. Never add a step that drops non-English audio.

## Operating it

- Tdarr is configured through its database API; the UI at tdarr.kebin.dev shows the same objects. Library `movies-webfriendly` uses flow `webfriendly-mp4`.
- The library is scoped to a single folder by default. To process more, edit the library's Source folder to `/data/Movies` and run a scan. The flow skips MP4s, so only MKVs are touched.
- The node needs at least one GPU transcode worker (Tdarr defaults to zero). Set it under Nodes, or the queue never drains.
- Work happens in `/srv/media/cache/tdarr` on local disk; the finished file is copied back to the NAS (cross-filesystem, so expect a copy, not a rename).
- Jellyfin picks up the new file on the next library scan; run one from the dashboard if you want it immediately. After a remux, check the default audio track in Jellyfin for multi-language files; Jellyfin 12 sometimes prefers a non-English track even when the AAC is flagged default.
