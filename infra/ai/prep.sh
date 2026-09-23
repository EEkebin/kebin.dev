set -uo pipefail
export XDG_RUNTIME_DIR=/run/user/1000
echo "== stop the old 27B quadlet and keep it from returning"
systemctl --user stop llama.service 2>/dev/null
mkdir -p ~/.config/containers/disabled
[ -f ~/.config/containers/systemd/llama.container ] && mv ~/.config/containers/systemd/llama.container ~/.config/containers/disabled/
systemctl --user daemon-reload
systemctl --user stop capstone-inference.service 2>/dev/null
systemctl --user disable capstone-inference.service 2>/dev/null
sleep 3
nvidia-smi --query-gpu=index,name,memory.used --format=csv,noheader

echo "== packages"
sudo bash -c 'export DEBIAN_FRONTEND=noninteractive; apt-get install -y -qq git unzip jq apache2-utils >/dev/null 2>&1; echo apt done'

echo "== uv"
command -v ~/.local/bin/uv >/dev/null || curl -LsSf https://astral.sh/uv/install.sh | sh >/dev/null 2>&1
~/.local/bin/uv --version

echo "== opencode"
curl -fsSL https://opencode.ai/install | bash >/dev/null 2>&1
ls ~/.opencode/bin/opencode ~/.local/bin/opencode 2>/dev/null
OC=$(ls ~/.opencode/bin/opencode ~/.local/bin/opencode 2>/dev/null | head -1); "$OC" --version 2>&1 | head -1

echo "== llama-swap"
mkdir -p ~/.local/share/llama-swap && cd ~/.local/share/llama-swap
TAG=$(curl -s https://api.github.com/repos/mostlygeek/llama-swap/releases/latest | jq -r .tag_name)
ASSET=$(curl -s https://api.github.com/repos/mostlygeek/llama-swap/releases/latest | jq -r '.assets[] | select(.name | test("linux_amd64.tar.gz$")) | .browser_download_url' | head -1)
echo "tag $TAG"; echo "asset $ASSET"
curl -sL "$ASSET" -o llama-swap.tar.gz && tar xzf llama-swap.tar.gz && rm -f llama-swap.tar.gz && ls -la . | awk 'NR>3{print $5,$9}'
./llama-swap --version 2>&1 | head -1

echo "== python for comfy"
~/.local/bin/uv python install 3.12 >/dev/null 2>&1; ~/.local/bin/uv python list --only-installed 2>/dev/null | head -3
echo "== torch cu126 wheels available for py3.12?"
~/.local/bin/uv pip install --dry-run --python 3.12 --index-url https://download.pytorch.org/whl/cu126 torch 2>&1 | grep -E "torch==|error" | head -3
