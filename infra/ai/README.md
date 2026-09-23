# AI VM (10.0.10.100)

Ubuntu 26.04, 8 vCPU, three passed-through GPUs. Everything runs as the `user` account under systemd user units (linger enabled), no root services.

| Device | Card | Used for |
|---|---|---|
| CUDA0 | Tesla V100 16 GB | default for LLMs and ComfyUI |
| CUDA1 | Tesla P100 16 GB | second card for split models, ComfyUI fallback |
| CUDA2 | Tesla M40 12 GB | parked, nothing points at it |

Driver 580 is the last branch that supports all three (Maxwell, Pascal, Volta). Everything CUDA is pinned to 12.x: llama.cpp is built with nvcc 12.4, PyTorch uses the `cu126` wheels, the last ones that ship sm_60/sm_70 kernels.

## Services

| Unit | Listens | What |
|---|---|---|
| `llama-swap.service` | 0.0.0.0:8080 | model router: OpenAI + Anthropic compatible API, loads whichever model a request names, unloads after idle |
| `opencode-web.service` | 0.0.0.0:4096 | OpenCode web UI + API, workspace `/srv/code/projects` |
| `comfyui.service` | 0.0.0.0:8188 | ComfyUI, default device CUDA0, fp32 VAE (fp16 VAE produces black images on Volta) |
| `tinyauth.service` (Quadlet) | 0.0.0.0:3000 | login page for code/comfy, used by nginx `auth_request` |
| `searxng.service` (Quadlet) | 0.0.0.0:8888 | web search for the agent |

Manage with `XDG_RUNTIME_DIR=/run/user/1000 systemctl --user <status|restart|stop> <unit>` when over SSH.

## Model routing (llama-swap)

`llama-swap/config.yaml` is the single place models are defined. Each entry is a full `llama-server` command line; `${PORT}` is filled in by llama-swap. Clients (OpenCode, the Capstone box, curl) ask for a model by name and the router starts it, swapping out whatever was loaded. Useful endpoints on :8080: `/v1/models`, `/running`, `POST /api/models/unload`.

Add a model: drop the GGUF (and its `mmproj` if it has vision) on disk, add an entry, `systemctl --user restart llama-swap`, add the same name to `opencode/opencode.json` so it shows in OpenCode's picker.

`--device CUDA0` pins a model to the V100. `--device CUDA0,CUDA1 --tensor-split 3,2` spreads it over both cards. The `llama-server` binary must be built for every card it touches: `build-multi/` was compiled with `-DCMAKE_CUDA_ARCHITECTURES="52;60;70"`; the older `build/` is Volta-only and aborts with "no kernel image" on the P100.

## GPU sharing

The V100 is shared by the LLM and ComfyUI. llama-swap's `ttl` unloads an idle model, so ComfyUI gets the full card after a quiet period. To free it immediately: `curl -X POST http://127.0.0.1:8080/api/models/unload`. ComfyUI's device can be changed per launch (`--cuda-device 1` for the P100).

## Install from scratch

1. `prep.sh` — stops legacy units, installs git/uv/OpenCode/llama-swap, Python 3.12.
2. `llama-swap/` config + unit, `opencode/` config + unit, `tinyauth/` env template + Quadlet, `comfyui/install.sh` (venv, torch cu126, ComfyUI + Manager, SDXL base, unit).
3. Public side: `infra/web/nginx/conf.d/{auth,code,comfy}.kebin.dev.conf` and `snippets/tinyauth.conf`; DNS A records for the same names.

## Storage note

Root disk is 125 GB and models are large (SDXL 7 GB, each 27B quant 11 to 13 GB). Check `df -h /` before adding models; a bigger model like Qwen3.6-35B-A3B at Q4 (21 GB) needs room freed first.
