# ScopeSentry (attack-surface management, feeds ARTEX)

ScopeSentry (autumn27) runs on the **ai VM (10.0.10.100)** as four podman
user-level quadlet containers, alongside ARTEX:

| unit                | role                                        | port (127.0.0.1 unless noted) |
|---------------------|---------------------------------------------|--------------------------------|
| `ss-mongodb`        | Mongo 7 (data)                              | 27017                          |
| `ss-redis`          | Redis 7 (queue)                             | 6379                           |
| `ss-server`         | web + API + MCP (`autumn27/scopesentry`)    | 8082 (published on all IFs)    |
| `ss-scan`           | scan worker (`autumn27/scopesentry-scan`)   | host network, no publish       |

Public: **https://scope.kebin.dev** — nginx vhost
(`infra/web/nginx/conf.d/scope.kebin.dev.conf`) with Tinyauth in front,
proxying to `10.0.10.100:8082`. DNS: Porkbun A record `scope.kebin.dev`
-> 76.170.99.205 (Cloudflare proxied, wildcard cert covers it).

## ARTEX wiring

- **Asset Sync**: configured via `POST /api/sync/scopesentry/datasource`
  with `{"url":"http://127.0.0.1:8082/mcp","api_key":"ssk_..."}`. This
  writes the `ScopeSentry` row in ARTEX's `mcp_servers` table (url +
  `X-API-Key` header) — the same row ARTEX uses for agent tools and for
  background asset sync.
- **ScopeSentry API key** (named `artex`): stored in
  `~/.config/scopesentry/api_key` on the ai VM (mode 0600). The value was
  shown once at creation; re-create in the UI (Settings -> API Keys) if lost.
- MCP row `browser` (playwright-mcp, host-installed) and `searxng` are also
  enabled; both MCPs granted to all agents in `agent_visibility`.

## Install / restore

```bash
cd infra/ai/scopesentry
bash setup.sh        # on the ai VM, as the artex user
```

Secrets live in `~/.config/scopesentry/env` (mode 0600) on the ai VM,
never in this repo — see `env.example`. Initial web login
(user + random password) is printed in the `ss-server` logs on first boot
and stored in the container's `PASSWORD` file
(`podman exec scope-sentry cat /opt/ScopeSentry/PASSWORD` style path;
also in the journal).

## Notes / gotchas

- Quadlet `Environment=` lines use literal `${VAR}` placeholders that
  `setup.sh` rewrites — do NOT use quadlet's `%VAR` specifier, it truncates
  long env names (e.g. `%MONGO_INITDB_ROOT_PASSWORD` -> `ONGO_...`).
- `HealthCmd` values are run through `/bin/sh`: no quotes or parens.
- Data volumes: `~/.local/share/scopesentry/{mongodb,redis,files,images,uploads}`.
- Timezone pinned to UTC.
