# Runbook: two versions of one episode (Jellyfin + Sonarr)

Used for Yu-Gi-Oh! Duel Monsters (2026-10-09): a Japanese set (jpn audio, English subs) and an English-dub set of the same 224 episodes shown as ONE show in Jellyfin with a version picker per episode.

## Layout

```
TV/Yu-Gi-Oh! Duel Monsters/Season 1/Yu-Gi-Oh! Duel Monsters - S01E01 - Japanese.mkv
TV/Yu-Gi-Oh! Duel Monsters/Season 1/Yu-Gi-Oh! Duel Monsters - S01E01 - English Dub.mkv
```

Jellyfin groups episode files that sit in the same season folder and parse to the same SxxEyy; the text after the last ` - ` becomes the version label. This is different from movies, where the file names must start with the folder name (the Harry Potter attempt failed because of that).

## Sonarr

Sonarr tracks one file per episode. With equal quality it keeps whichever it scanned first, so the custom format **Japanese version (local)** (release-title regex ` - Japanese\.\w+$`) is scored +10 in the **Any** profile; the dub file then fails "Not a Custom Format upgrade" and the Japanese file always stays the tracked one. That profile has upgrades off, so Sonarr will not grab anything that could replace the Japanese file. Recyclarr does not manage the Any profile.

Do not click **Rename files** for this series: the naming format would strip the ` - Japanese` suffix.

## How the move was done

Absolute numbers (001 to 224) were mapped to seasons with Sonarr's own episode list (tvdb 76894). Every move is logged in `/srv/media/yugioh-reorg-2026-10-09.json` on the media VM. The three movie files that came with the Japanese set are byte-identical duplicates of the Movies library copies and were left in `TV/.Yu-Gi-Oh! leftover (...)`, a dot folder that Jellyfin and Sonarr ignore.
