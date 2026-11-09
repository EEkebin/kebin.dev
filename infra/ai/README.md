# AI VM (10.0.10.100)

Ubuntu 26.04, 8 vCPU, no GPU and no NAS mount. Everything runs as the `user` account under systemd user units (linger enabled), no root services.

This VM holds the AI apps. The GPUs, llama-swap and ComfyUI are on the media VM (`infra/media/llama-swap/`, `infra/media/comfyui/`), and the apps reach the model over the network. The agent (OpenCode runs shell commands) stays here on purpose: this VM has no mount of the files on the NAS.

## Services

| Unit | Listens | What |
|---|---|---|
| `llama-proxy.socket` | 0.0.0.0:8080 | forwards the old model address to llama-swap on the media VM, so the Capstone tunnel and LAN clients keep working |
| `opencode-web.service` | 0.0.0.0:4096 | OpenCode 2 (`opencode serve`): web UI + API, workspace `/srv/code/projects`, password in `~/.config/opencode/server.env` |
| `tinyauth.service` (Quadlet) | 0.0.0.0:3000 | login page for code/comfy, used by nginx `auth_request` |
| `searxng.service` (Quadlet) | 0.0.0.0:8888 | SearXNG metasearch (Brave + Google CSE engines), JSON format enabled; its page is search.kebin.dev behind Tinyauth |
| `postgres.service` (Quadlet) | 0.0.0.0:5432 | PostgreSQL, `pgautoupgrade` image (latest major, upgrades its own data folder), logins only from 10.0.0.0/24, 10.0.10.0/24, 10.0.20.0/24 |
| `humanizer.service` | 0.0.0.0:8095 | the humanize.kebin.dev page: builds the humanizer model's fixed prompt and streams the rewrite from llama-swap on the media VM |
| `sillytavern.service` (Quadlet) | 0.0.0.0:8010 | SillyTavern for tavern.kebin.dev, data in `~/.local/share/sillytavern`, models from llama-swap on the media VM |
| `mcp-searxng.service` (Quadlet) | 0.0.0.0:8899 | MCP server (streamable HTTP) that exposes SearXNG as `searxng_web_search`, `searxng_search_suggestions`, `web_url_read` tools |

Manage with `XDG_RUNTIME_DIR=/run/user/1000 systemctl --user <status|restart|stop> <unit>` when over SSH.

Weekly updates: `ai-update.timer` (Sunday 04:45 Pacific, 11:45 on the VM's UTC clock) runs `update/ai-update.sh`, which does `podman auto-update` for the Quadlets marked `AutoUpdate=registry` (searxng, mcp-searxng, tinyauth) and `opencode upgrade`. llama.cpp, ComfyUI and the models are manual, see `docs/runbooks/updates.md`. The llama-swap dashboard is public at https://ai.kebin.dev/ui/ behind a Tinyauth login (the API under `/v1/` keeps the bearer key).

## Model routing (llama-swap)

llama-swap runs on the media VM (`media-llama-swap.service`, port 8086, binaries in `/srv/media/llama`). `infra/media/llama-swap/config.yaml` is the single place models are defined. Each entry is a full `llama-server` command line; `${PORT}` is filled in by llama-swap. Clients (OpenCode, the Capstone box, curl) ask for a model by name and the router starts it, swapping out whatever was loaded. Useful endpoints on :8086: `/v1/models`, `/running`, `POST /api/models/unload`.

Models live on the NAS: `/mnt/storage/AI/models/<model>/`, through the media VM's mount. The NAS reads at about 770 MB/s against 355 MB/s for a VM disk, so loading from it is faster too. Every entry runs with `--load-mode none` (this build's spelling of no-mmap; `--no-mmap` is rejected): the parts that stay on the CPU (token embeddings) are copied into RAM at load, so a running model never touches the share again and an NFS hiccup cannot stall it.

| Model | Folder | Where it runs |
|---|---|---|
| `qwen3.8-27b` (the main model, aliases `capstone-qwen`, `qwen`) | `qwen3.8-27b/` (Q8_0, plus the old UD-Q3_K_XL / IQ3_XXS quants and an MTP draft) | all three cards, split 5.6/6.4/5 (about 14.9/15.5/13.1 GB, leaving about 3 GB on CUDA2 for transcodes), 262K with a q8_0 KV cache, vision |
| `humanizer` | `humanizer/` (Q8_0 + `prompt_format.json`) | all three cards, 8K, completion only |
| `artemis`, `dark-craving` | `artemis/`, `dark-craving/` (Q8_0) | all three cards, 64K, for SillyTavern; unload after 30 idle minutes |

One model is loaded at a time: asking for a different one unloads the current one first (about 70 s for the 27B, less for the humanizer). The 27B is preloaded when llama-swap starts and unloads after 15 idle minutes, so ComfyUI gets CUDA0 back; the humanizer unloads after 5 idle minutes. Either comes back on the next request for it.

Add a model: drop the GGUF (and its `mmproj` if it has vision) in its folder on the share, add an entry, `systemctl --user restart llama-swap`, add the same name to `opencode/opencode.json` so it shows in OpenCode's picker.

`--device CUDA0` pins a model to one card. `--tensor-split` sets how a model spreads over the listed cards. The binaries in `/srv/media/llama/bin` are the `build-multi` llama.cpp build plus copies of the CUDA libraries it needs (`libcudart`, `libcublas`, `libgomp`), because the media VM has no CUDA toolkit. Driver 580 is the last branch for Volta, and CUDA stays on 12.x (nvcc 12.4, PyTorch `cu126`). No FP8 or bf16 on these cards, so GGUF with F16 it is.

## Web access for the agent

OpenCode has three ways to reach the web; `opencode/opencode.json` sets which are on:

| Tool | Where it goes | Setting |
|---|---|---|
| `searxng_web_search` (MCP) | local SearXNG on :8888, which fans out to Brave/Google | `mcp.searxng` remote `http://127.0.0.1:8899/mcp`, permission `searxng_*: allow` |
| `webfetch` (built in) | fetches one URL straight from the VM and converts it to markdown | `allow` |
| `websearch` (built in) | Exa's hosted MCP at mcp.exa.ai, a third party | `deny` |

Search stays on the box, page reads are direct, nothing goes through a hosted search API. The MCP container runs on the host network so it can reach SearXNG on loopback. `MCP_HTTP_HOST=0.0.0.0` so the web VM can proxy it as search.kebin.dev; `MCP_HTTP_ALLOWED_HOSTS` lists that name plus the local addresses and `MCP_HTTP_TRUST_PROXY` honours nginx's X-Forwarded headers. SearXNG's own config lives in `~/llama/searxng/settings.yml` (`searxng/settings.yml.example` here, `secret_key` must be random); the `json` format must stay enabled or the MCP gets 403.

Check: `opencode mcp list` shows `searxng connected`; `curl 127.0.0.1:8899/health`.

Remote installs (kebin.dev/cli) get the same tool through `https://search.kebin.dev/mcp`, gated by the ai.kebin.dev bearer key and passed as an `Authorization` header in the `mcp.searxng` entry; nothing runs on the user's machine.

## CLI installers (kebin.dev/cli)

The page has a tab per tool, each with install and uninstall scripts for Linux/macOS (`.sh`) and Windows (`.ps1`), all in `site/cli/`. nginx fills the API key into the page.

| Tool | Scripts | What it sets up |
|---|---|---|
| OpenCode | `install`, `uninstall` | `aibox` provider and `searxng` MCP in `~/.config/opencode/opencode.json` |
| Claude Code | `claude-install`, `claude-uninstall` | a `claude-local` command: `ANTHROPIC_BASE_URL=https://ai.kebin.dev`, the key as `ANTHROPIC_AUTH_TOKEN`, model `qwen3.8-27b`, its own `CLAUDE_CONFIG_DIR` (`~/.claude-local`) with the `searxng` MCP |
| Codex | `codex-install`, `codex-uninstall` | a `codex-local` command: its own `CODEX_HOME` (`~/.codex-local`) with an `aibox` provider (Responses API) and model `qwen3.8-27b`; on Windows also `[windows] sandbox = "elevated"` |

The key lives in `~/.config/kebin/aibox.env`, shared by `claude-local` and `codex-local`. Neither touches the user's normal `claude`/`codex` login or history. Codex has no web search here: with an unknown model it keeps MCP tools away from the model, and a custom `model_catalog_json` made things worse.

## OpenCode 2

This VM and the CLI installers run OpenCode 2, which ships separately from 1.x: the installer is `https://opencode.ai/v2/install` and the npm package is `@opencode/cli`, not `opencode-ai`. `opencode upgrade` stays on the 2.x line. The two share the `opencode` command and the config locations, so they can't sit side by side. `opencode/opencode.json` stays in the 1.x format, which V2 still reads; converting it to V2's native format is optional.

What changed for this setup:

- `opencode web` is gone; `opencode serve` hosts the web app.
- The server always requires a password. `~/.config/opencode/server.env` holds `OPENCODE_SERVER_PASSWORD`, and nginx sends it as Basic auth (user `opencode`) from `/etc/nginx/secrets/code-auth.conf`, so Tinyauth stays the only login. Change one, change both.
- V2 no longer asks before touching paths outside the project unless told to, so the config sets `external_directory` to `ask`.
- V2 doesn't run language servers. LSP tools and diagnostics are gone, so the agent relies on lint, typecheck and compiler commands.
- The shared background service is off on this VM (`opencode service set disabled true`), because `opencode-web.service` is the server.

## PostgreSQL

`postgres/postgres.container` runs `docker.io/pgautoupgrade/pgautoupgrade:latest`: the official PostgreSQL image plus an automatic `pg_upgrade` on start when the data folder belongs to an older major. That is what makes a `latest` tag safe here; a plain `postgres:latest` would refuse to start after a major release. Data lives in `~/.local/share/postgres` (the parent of PGDATA, so two majors can coexist during an upgrade), credentials in `~/.config/postgres/env` (`postgres/env.example`), allowed client networks in `~/.config/postgres/pg_hba.conf` (mounted read-only, change it and `systemctl --user restart postgres`). Connect: host 10.0.10.100, port 5432, user `admin`, database `postgres`, password required (scram). JSONB needs nothing extra. No extensions are installed; `pgvector` would mean switching to the `pgvector/pgvector` image, which does not auto-upgrade.

Backups: `pg-backup.timer` dumps everything daily (10:30 UTC) to `~/.local/share/postgres-backups`, keeps 7, and `ai-update.sh` takes one more dump before any image update and aborts the update if the dump fails. Restore: `zcat <dump> | podman exec -i postgres psql -U admin -d postgres`.

OPNsense: WLAN clients need a rule allowing 10.0.20.0/24 to 10.0.10.100 tcp 5432; LAN to VM LAN is already open.

## Humanizer

`humanizer/` holds the page behind humanize.kebin.dev. The model ([jialinyyzz/humanizer](https://huggingface.co/jialinyyzz/humanizer), a Gemma 4 12B fine-tune, Apache 2.0) rewrites a draft so it reads less like a language model wrote it. It is a completion model, not a chat model: the prompt must be exactly `instr + "

" + draft + sep` from its `prompt_format.json`, sampled at temperature 1.0 / top-p 0.95 with top-k, min-p and repeat penalty off, stopping only on EOS. `humanizer.py` builds that prompt (and refuses to start if it no longer hashes to the fingerprint in the file), sends it to llama-swap's `/v1/completions` on the media VM and streams the result. Drafts are capped at 12,000 characters because instruction, draft and rewrite share an 8K window.

Install: `humanizer.py`, `index.html` and `prompt_format.json` to `~/.local/share/humanizer/`, the unit to `~/.config/systemd/user/`, `systemctl --user enable --now humanizer`.

## GPU sharing

All on the media VM: llama-swap's model spans the three cards, ComfyUI is pinned to CUDA0, Jellyfin and Tdarr to CUDA2. VRAM has no hard limits here, so the model's split is what keeps room for transcodes. ComfyUI needs the 27B unloaded (about 8 GB for SDXL): it idles out after 15 minutes, or free it now with `curl -X POST http://10.0.10.30:8086/api/models/unload`.

## Install from scratch

1. `prep.sh` — stops legacy units, installs git/uv/OpenCode/llama-swap, Python 3.12.
2. `opencode/` config + unit (write `~/.config/opencode/server.env` first, then `opencode service set disabled true`), `tinyauth/` env template + Quadlet, `comfyui/install.sh` (venv, torch cu126, ComfyUI + Manager, SDXL base, unit).
3. `postgres/` (Quadlet, `env.example` -> `~/.config/postgres/env`, `pg_hba.conf` -> `~/.config/postgres/`, `pg-backup.sh` -> `~/.config/`, the two backup units -> `~/.config/systemd/user/`, then `systemctl --user enable --now pg-backup.timer`); `searxng/` Quadlets (copy `settings.yml.example` to `~/llama/searxng/settings.yml` with a random `secret_key`); `update/` script + user units (`ai-update.sh` goes to `~/.config/`, the units to `~/.config/systemd/user/`, then `systemctl --user enable --now ai-update.timer`).
4. Public side: `infra/web/nginx/conf.d/{auth,code,comfy}.kebin.dev.conf` and `snippets/tinyauth.conf`; DNS A records for the same names.

## Storage note

Root disk is 125 GB and holds no models now: LLM weights are on the NAS, ComfyUI's checkpoints on the media VM.
