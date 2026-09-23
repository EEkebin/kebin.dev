set -uo pipefail
export PATH=$HOME/.local/bin:$PATH
D=$HOME/.local/share/comfyui
mkdir -p "$D" && cd "$D"
echo "== clone"
[ -d ComfyUI/.git ] || git clone -q https://github.com/comfyanonymous/ComfyUI.git
cd ComfyUI && git log --oneline -1
echo "== venv (python 3.12, torch cu126 = last CUDA build with Volta sm_70 and Pascal sm_60 kernels)"
[ -d .venv ] || uv venv --python 3.12 .venv >/dev/null
. .venv/bin/activate
uv pip install -q --index-url https://download.pytorch.org/whl/cu126 torch torchvision torchaudio 2>&1 | tail -2
uv pip install -q -r requirements.txt 2>&1 | tail -2
python - <<'PY'
import torch
print("torch", torch.__version__, "cuda", torch.version.cuda, "| arch list:", torch.cuda.get_arch_list())
for i in range(torch.cuda.device_count()):
    p = torch.cuda.get_device_properties(i); print(f"  cuda:{i} {p.name} sm_{p.major}{p.minor} {p.total_memory//2**20} MiB")
x = torch.randn(2048, 2048, device="cuda:0", dtype=torch.float16); y = (x @ x).sum().item(); print("fp16 matmul on cuda:0 ok")
PY
echo "== ComfyUI-Manager"
cd custom_nodes && { [ -d ComfyUI-Manager ] || git clone -q https://github.com/Comfy-Org/ComfyUI-Manager.git; } && cd ..
uv pip install -q -r custom_nodes/ComfyUI-Manager/requirements.txt 2>&1 | tail -1
echo "== SDXL base checkpoint (6.9 GB)"
mkdir -p models/checkpoints
[ -f models/checkpoints/sd_xl_base_1.0.safetensors ] || curl -sL -o models/checkpoints/sd_xl_base_1.0.safetensors "https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/sd_xl_base_1.0.safetensors"
ls -la models/checkpoints/ | awk 'NR>3{print $5,$9}'
echo "== unit"
mkdir -p ~/.config/systemd/user
cat > ~/.config/systemd/user/comfyui.service <<U
[Unit]
Description=ComfyUI on 127.0.0.1:8188 (default device: V100)
After=network-online.target

[Service]
WorkingDirectory=$D/ComfyUI
Environment=CUDA_DEVICE_ORDER=PCI_BUS_ID
ExecStart=$D/ComfyUI/.venv/bin/python main.py --listen 0.0.0.0 --port 8188 --cuda-device 0 --fp32-vae --preview-method auto
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
U
export XDG_RUNTIME_DIR=/run/user/1000
systemctl --user daemon-reload && systemctl --user enable --now comfyui.service
for i in $(seq 1 40); do curl -sf -o /dev/null http://127.0.0.1:8188/system_stats && break; sleep 3; done
curl -s http://127.0.0.1:8188/system_stats | python3 -c 'import sys,json; d=json.load(sys.stdin); print("comfy", d["system"]["comfyui_version"], "| torch", d["system"]["pytorch_version"]); [print("  device:", x["name"], x["vram_total"]//2**20, "MiB") for x in d["devices"]]'
df -h / | tail -1
