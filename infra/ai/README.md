# AI VM (10.0.10.100)

Ubuntu 26.04, 8 vCPU, three passed-through GPUs. Everything runs as the `user` account under systemd user units (linger enabled), no root services.

| Device | Card | Used for |
|---|---|---|
| CUDA0 | Tesla V100 PCIe 16 GB | a third of whichever model is loaded; ComfyUI |
| CUDA1 | Tesla V100 PCIe 16 GB | a third of whichever model is loaded |
| CUDA2 | Tesla V100 SXM2 16 GB (on a PCIe adapter) | a third of whichever model is loaded |

48 GB of VRAM, all Volta (sm_70). Driver 580 is the last branch that supports Volta. Everything CUDA is pinned to 12.x: llama.cpp is built with nvcc 12.4, PyTorch uses the `cu126` wheels (CUDA 13 dropped Volta). No FP8 or bf16 on these cards, so FP8 checkpoints and bf16 files are no use here; GGUF with F16 is.

## Services

| Unit | Listens | What |
|---|---|---|
| `llama-swap.service` | 0.0.0.0:8080 | model router: OpenAI + Anthropic compatible API, loads whichever model a request names, unloads after idle |
| `opencode-web.service` | 0.0.0.0:4096 | OpenCode web UI + API, workspace `/srv/code/projects` |
| `comfyui.service` | 0.0.0.0:8188 | ComfyUI, default device CUDA0, fp32 VAE (fp16 VAE produces black images on Volta) |
| `tinyauth.service` (Quadlet) | 0.0.0.0:3000 | login page for code/comfy, used by nginx `auth_request` |
| `searxng.service` (Quadlet) | 0.0.0.0:8888 | SearXNG metasearch (Brave + Google CSE engines), JSON format enabled; its page is search.kebin.dev behind Tinyauth |
| `postgres.service` (Quadlet) | 0.0.0.0:5432 | PostgreSQL, `pgautoupgrade` image (latest major, upgrades its own data folder), logins only from 10.0.0.0/24, 10.0.10.0/24, 10.0.20.0/24 |
| `humanizer.service` | 0.0.0.0:8095 | the humanize.kebin.dev page: builds the humanizer model's fixed prompt and streams the rewrite from llama-swap |
| `mcp-searxng.service` (Quadlet) | 0.0.0.0:8899 | MCP server (streamable HTTP) that exposes SearXNG as `searxng_web_search`, `searxng_search_suggestions`, `web_url_read` tools |

Manage with `XDG_RUNTIME_DIR=/run/user/1000 systemctl --user <status|restart|stop> <unit>` when over SSH.

Weekly updates: `ai-update.timer` (Sunday 04:45 Pacific, 11:45 on the VM's UTC clock) runs `update/ai-update.sh`, which does `podman auto-update` for the Quadlets marked `AutoUpdate=registry` (searxng, mcp-searxng, tinyauth) and `opencode upgrade`. llama.cpp, ComfyUI and the models are manual, see `docs/runbooks/updates.md`. The llama-swap dashboard is public at https://ai.kebin.dev/ui/ behind a Tinyauth login (the API under `/v1/` keeps the bearer key).

## Model routing (llama-swap)

`llama-swap/config.yaml` is the single place models are defined. Each entry is a full `llama-server` command line; `${PORT}` is filled in by llama-swap. Clients (OpenCode, the Capstone box, curl) ask for a model by name and the router starts it, swapping out whatever was loaded. Useful endpoints on :8080: `/v1/models`, `/running`, `POST /api/models/unload`.

Models live on the NAS, not the VM disk: `/mnt/storage/AI/models/<model>/` (NFS, the same share the media VM mounts, `x-systemd.automount` in `/etc/fstab` so boot never waits for it). The NAS reads at about 770 MB/s against 355 MB/s for the VM's own disk, so loading from it is faster too. Every entry runs with `--load-mode none` (this build's spelling of no-mmap; `--no-mmap` is rejected): the parts that stay on the CPU (token embeddings) are copied into RAM at load, so a running model never touches the share again and an NFS hiccup cannot stall it.

| Model | Folder | Where it runs |
|---|---|---|
| `qwen3.8-27b` (the main model, aliases `capstone-qwen`, `qwen`) | `qwen3.8-27b/` (Q8_0, plus the old UD-Q3_K_XL / IQ3_XXS quants and an MTP draft) | all three cards, even split, 262K with a q8_0 KV cache, vision |
| `humanizer` | `humanizer/` (Q8_0 + `prompt_format.json`) | all three cards, 8K, completion only |

One model is loaded at a time: asking for a different one unloads the current one first (about 70 s for the 27B, less for the humanizer). The 27B is preloaded when llama-swap starts and has no idle timeout; the humanizer unloads after 5 idle minutes, and the 27B comes back on the next request for it.

Add a model: drop the GGUF (and its `mmproj` if it has vision) in its folder on the share, add an entry, `systemctl --user restart llama-swap`, add the same name to `opencode/opencode.json` so it shows in OpenCode's picker.

`--device CUDA0` pins a model to one card. `--device CUDA0,CUDA1,CUDA2 --tensor-split 1,1,1` spreads it evenly. `build-multi/` (compiled for sm 52/60/70 back when a P100 and an M40 were in the VM) is what the config points at; the Volta-only `build/` would do just as well now.

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

## PostgreSQL

`postgres/postgres.container` runs `docker.io/pgautoupgrade/pgautoupgrade:latest`: the official PostgreSQL image plus an automatic `pg_upgrade` on start when the data folder belongs to an older major. That is what makes a `latest` tag safe here; a plain `postgres:latest` would refuse to start after a major release. Data lives in `~/.local/share/postgres` (the parent of PGDATA, so two majors can coexist during an upgrade), credentials in `~/.config/postgres/env` (`postgres/env.example`), allowed client networks in `~/.config/postgres/pg_hba.conf` (mounted read-only, change it and `systemctl --user restart postgres`). Connect: host 10.0.10.100, port 5432, user `admin`, database `postgres`, password required (scram). JSONB needs nothing extra. No extensions are installed; `pgvector` would mean switching to the `pgvector/pgvector` image, which does not auto-upgrade.

Backups: `pg-backup.timer` dumps everything daily (10:30 UTC) to `~/.local/share/postgres-backups`, keeps 7, and `ai-update.sh` takes one more dump before any image update and aborts the update if the dump fails. Restore: `zcat <dump> | podman exec -i postgres psql -U admin -d postgres`.

OPNsense: WLAN clients need a rule allowing 10.0.20.0/24 to 10.0.10.100 tcp 5432; LAN to VM LAN is already open.

## Humanizer

`humanizer/` holds the page behind humanize.kebin.dev. The model ([jialinyyzz/humanizer](https://huggingface.co/jialinyyzz/humanizer), a Gemma 4 12B fine-tune, Apache 2.0) rewrites a draft so it reads less like a language model wrote it. It is a completion model, not a chat model: the prompt must be exactly `instr + "

" + draft + sep` from its `prompt_format.json`, sampled at temperature 1.0 / top-p 0.95 with top-k, min-p and repeat penalty off, stopping only on EOS. `humanizer.py` builds that prompt (and refuses to start if it no longer hashes to the fingerprint in the file), sends it to llama-swap's `/v1/completions` and streams the result. Drafts are capped at 12,000 characters because instruction, draft and rewrite share an 8K window.

Install: `humanizer.py` and `index.html` to `~/.local/share/humanizer/`, the unit to `~/.config/systemd/user/`, `systemctl --user enable --now humanizer`.

## GPU sharing

All three cards belong to whichever model llama-swap has loaded; ComfyUI also uses CUDA0. llama-swap's `ttl` unloads an idle model, so ComfyUI gets the full card after a quiet period. To free it immediately: `curl -X POST http://127.0.0.1:8080/api/models/unload`. ComfyUI's device can be changed per launch (`--cuda-device 2` for the third V100).

## Install from scratch

1. `prep.sh` — stops legacy units, installs git/uv/OpenCode/llama-swap, Python 3.12.
2. `llama-swap/` config + unit, `opencode/` config + unit, `tinyauth/` env template + Quadlet, `comfyui/install.sh` (venv, torch cu126, ComfyUI + Manager, SDXL base, unit).
3. `postgres/` (Quadlet, `env.example` -> `~/.config/postgres/env`, `pg_hba.conf` -> `~/.config/postgres/`, `pg-backup.sh` -> `~/.config/`, the two backup units -> `~/.config/systemd/user/`, then `systemctl --user enable --now pg-backup.timer`); `searxng/` Quadlets (copy `settings.yml.example` to `~/llama/searxng/settings.yml` with a random `secret_key`); `update/` script + user units (`ai-update.sh` goes to `~/.config/`, the units to `~/.config/systemd/user/`, then `systemctl --user enable --now ai-update.timer`).
4. Public side: `infra/web/nginx/conf.d/{auth,code,comfy}.kebin.dev.conf` and `snippets/tinyauth.conf`; DNS A records for the same names.

## Storage note

Root disk is 125 GB. LLM weights are on the NAS (see Model routing), so they do not count against it; ComfyUI's checkpoints (SDXL 7 GB) still live on the VM disk.
