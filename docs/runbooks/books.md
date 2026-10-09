# Runbook: books and audiobooks

Readarr was retired in 2025 (its metadata source died). The stack here is two apps:

| App | Where | What |
|---|---|---|
| Audiobookshelf | books.kebin.dev, public with its own accounts | the library and the player for audiobooks and ebooks, with phone apps. One library "Books" with two folders: the existing `Media/Books` share and `Media/Downloads/books` (where Shelfmark delivers) |
| Shelfmark | shelfmark.kebin.dev, behind Tinyauth | search and download books/audiobooks from public sources; downloads land in `Media/Downloads/books` and show up in Audiobookshelf after a scan |

Audiobookshelf does not need the folder split (ebooks and audiobooks can share one library). Items Shelfmark delivers can be moved from `Downloads/books` into `Books` whenever tidy; Audiobookshelf rescans both.

Shelfmark's own login is off on purpose: nginx puts Tinyauth in front. Its standard image ships Chromium to pass Cloudflare checks on direct-download sources, so it wants about 2 GB of RAM headroom on the media VM.

Jellyfin's "Books" library is now redundant; it can be removed from Jellyfin without touching files.

Audiobookshelf first-run (done by `infra/media/scripts/wire.sh` logic, or by hand): `POST /init` creates the root user, `POST /api/libraries` creates the library, then a scan. Admin login is the standard admin account.
