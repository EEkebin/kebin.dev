# ARTEX (autonomous pentest)

[BaaRai/ARTEX](https://github.com/BaaRai/ARTEX) v0.7.0, community continuation of the original ARTEX (Autumn-27, repo withdrawn).
Self-hosted LLM multi-agent penetration testing: a planner dispatches intents, workers run real tools
(nmap, nuclei, httpx, katana, ffuf, sqlmap...), findings are bound to captured HTTP traffic as evidence.

Public: https://artex.kebin.dev (Tinyauth, then the ARTEX admin login)

## Layout (ai VM)

| Path | What |
|---|---|
| `/srv/artex/` | release files: `artex` binary, `start.sh` (daemon wrapper — always start through it), `skills/`, `config.json` (600, DB connection) |
| `/srv/artex/data/` | runtime data: traffic blobs, transcripts, task files, task archives |
| `/srv/artex/jwt.key`, `/srv/artex/secret.key` | session key + AES-256-GCM key for secrets stored in the DB — **back up with the DB** |
| `/srv/artex/.pg.env` | Postgres password (600); the Quadlet env file also lives at `~/.config/artex/pg.env` |
| `/srv/artex/.admin-pass` | the one admin password (600). Username is hardcoded `ARTEX` by the app. |
| `~/.local/share/artex/pgdata/` | dedicated Postgres 16 data dir (port **5433**; 5432 is the main PG for SillyTavern/tinyauth) |
| `~/.config/systemd/user/artex.service` | the app (from `artex.service` here) |
| `~/.config/containers/systemd/artex-postgres.container` | the DB (Quadlet, from `artex-postgres.container` here) |

The release zip was verified with `sha256sum -c SHA256SUMS` from the official v0.7.0 release
(provenance attestations are not attached to v0.7.0 zips; they start with the next tag).
Install the same way for a fresh box: download the zip + `SHA256SUMS` from the release, verify, unzip.

## Model + search wiring

- LLM profile `local-qwen` (in-app, System → LLM): OpenAI format, base URL `http://10.0.10.30:8086/v1`
  (llama-swap on the media VM), model `qwen3.8-27b-abliterated`. No key leaves the LAN.
  The `ARTEX_LLM_*` env in the unit is the same values as a global fallback.
- Web search: System → MCP has a `searxng` server (`https://search.kebin.dev/mcp`, bearer in `env`).
  The SearXNG API key is the same `aibox` key as everything else; refresh it in the DB row if it rotates.

## Ops

- **Update:** back up (below) → download the new release zip → verify SHA256 → stop the service →
  overwrite `artex` + `skills/` (keep `config.json`, `data/`, `keys/`) → start. The binary applies
  `schema.sql` + numbered migrations at startup; no manual DB step.
- **Backup:** ARTEX ships `scripts/backup.sh` (not in the release zip; from the repo at the installed
  tag). A DB dump is useless without `keys/secret.key`. Cron lives in `pg-backup.sh` style on this VM;
  the daily backup covers this Postgres via:
  covered by `artex-backup.sh` (pg_dump + `data/` + `jwt.key` + `secret.key`, daily timer, keep 7).
- **Reinstall from backup:** restore the pgdata or dump, keep the same `keys/`, restart.

## Security notes

- UI binds 127.0.0.1 only; the 8788 traffic-capture proxy is off unless enabled.
- The app has its own per-IP login rate limit (10/min); `ARTEX_TRUSTED_PROXIES=10.0.10.20/32`
  makes it read X-Forwarded-For from the web VM.
- Untrusted tool output framing (prompt-injection boundary) is on by default — leave it.
- Scope tasks to own/authorized targets only (license + good sense). First suggested target: kebin.dev itself.
