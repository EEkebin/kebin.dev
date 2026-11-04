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
# Runs from the comfyui service in infra/media/compose.yml: keep this folder at /srv/media/config/comfyui/ComfyUI and uv's Python at /srv/media/config/comfyui/uv.
