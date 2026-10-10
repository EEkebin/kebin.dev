# Runbook: archive.org torrents that stall

Internet Archive torrents have no real peers; the only sources are archive.org's **web seeds**. Two things make them sit at "stalled" for days (seen with the League of Legends patch-system items, 2026-10-04..09):

1. **Data-node errors poison the seed.** `https://archive.org/download/` redirects each file to a data node (`dnNNNNNN.ca.archive.org`). Those nodes return the odd `500 Internal Server Error`; libtorrent then marks the original seed as not having that file (peer flag `K`, "not interested") and after a few failures bans it ("URL seed connection failed ... peer banned"). The torrent shows 0 B/s with archive.org peers connected, while a plain `curl -r 0-10000000` of the same file works at full speed. The state lives in memory, so it never recovers on its own. Fix: remove and re-add the torrent's web seed URLs (WebUI: torrent → Web seeds tab, or `torrents/removeWebSeeds` + `addWebSeeds` in the API). `media-qb-webseed.timer` does exactly that every 2 minutes for every torrent in "stalled" state that has web seeds; log in `/var/log/media-qb-webseed.log`. A qBittorrent restart also clears it.

2. **archive.org rewrites its own metadata files** (`*_meta.xml`, `*_meta.sqlite`, sometimes `*_files.xml`) after the torrent was made. The pieces holding them can never pass the hash check, so the torrent stops at 99.9x%. Fix: set those files to "Do not download". In these items each sits in its own piece, so nothing else is affected. When a changed file shares a piece with content you want (small items with small pieces), skip the sharing files too and download them straight from `https://archive.org/download/<item>/<file>` into the torrent's folder; compare sizes with the torrent's file list first.

Check an item for changes: `https://archive.org/metadata/<item>` lists current file sizes; compare with the torrent's file list. The `<item>_archive.torrent` on the item is regenerated too, but its infohash was unchanged in every case seen, so re-adding the torrent does not help.

## Skip the torrent: the download portal (2026-10-09)

Even with the kick timer the torrents averaged 1-10 MB/s on a line that pulls 110-130 MB/s from archive.org with a few parallel connections, because libtorrent keeps one connection per seed and waits 30 s after every 500. Big archive.org items, and any other direct link, go through the download portal instead:

- **downloads.kebin.dev** (Tinyauth) is AriaNg on top of **aria2** (`aria2` and `ariang` containers in `compose.yml`, downloads in `/mnt/storage/Media/Downloads`, config in `/srv/media/config/aria2/aria2.conf`). Add links, torrents or magnets; pause, resume, cancel one or all; set the global speed limit under AriaNg Settings → aria2 Settings → Max Overall Download Limit. Files are fetched with up to 16 connections each and resume after restarts.
- First use in a browser: open the one-click settings link from the handoff document, which fills in the RPC address and secret (`ARIA2_RPC_SECRET` in `/srv/media/.env`). Nothing else to configure.
- **downloads.kebin.dev/ia/** (`media-ia-queue.service`, `/srv/media/ia-queue.py`): paste an archive.org link or identifier and every original file of the item is queued with its MD5 from the manifest, so aria2 verifies each file after download (a mismatch shows as an error in the portal). "Preview only" lists the files and total size without queueing.

### aria2 settings that differ from the image defaults

Set once after the first start, in `/srv/media/config/aria2/` (the image generates both files; a sed in a fresh install must run after `podman-compose up`):

- `aria2.conf`: `max-connection-per-server=16`, `split=16`, `min-split-size=8M`, `file-allocation=none` (NFS), `follow-torrent=false`, `follow-metalink=false` (a downloaded `.torrent` is just a file; to download via BitTorrent upload the .torrent in AriaNg or paste a magnet).
- `script.conf`: `delete-empty-dir=false` (the default **deleted every empty folder under Downloads**, including qBittorrent's `incomplete/` and category folders, 2026-10-09), `delete-dot-torrent=false` (archive.org items contain .torrent files as content), `delete-on-error=false` and `delete-on-removed=false` (keep files when a task errors or is removed; the helper removes and re-adds tasks, and a cancelled partial can be resumed with `continue`).

### Verification and the slot count (lessons from 2026-10-09)

- Do **not** pass aria2 a `checksum` option for big files. aria2 checks one file at a time at ~90 MB/s on the NAS and a finished file keeps its download slot until checked, so the slots filled with files waiting to be hashed and downloads starved. The helper's verifier thread hashes finished files instead (one at a time; three parallel readers stalled aria2's single-threaded event loop so badly that its RPC took 30 s and the portal looked dead). State: `/srv/media/ia-verify.json`; log: `/var/log/media-ia-queue.log`. A mismatch deletes the file and re-queues it, twice at most, then the /ia/ table shows it in red.
- `max-concurrent-downloads` is 20 (set live with `aria2.changeGlobalOption`; the file says 5 until edited). More than that only adds NAS contention.
- archive.org's own `_files.xml`, `_meta.xml`, `_meta.sqlite`, `_reviews.xml` are rewritten by archive.org whenever an item is touched, so their manifest MD5 never matches; the helper skips them.
