#!/bin/bash
# Keeps the media VM's model server on the newest llama.cpp and llama-swap.
#
#   1. builds the newest llama.cpp build tag (bNNNNN) for the V100s (sm_70, CUDA 12.9) inside a container
#   2. downloads the newest llama-swap release
#   3. switches /srv/media/llama/bin and /srv/media/llama/llama-swap to them and restarts llama-swap
#   4. asks the default model for a short answer; if that fails, switches back and restarts again
#
# Runs weekly from media-llama-update.timer. By hand:  sudo /srv/media/llama/update-llama.sh [--force]
# --force rebuilds even when the newest tag is already installed. Log: /var/log/media-llama-update.log
set -euo pipefail

BASE=/srv/media/llama
REL=$BASE/releases            # one folder per llama.cpp build: releases/b12723/{llama-server,lib*.so*}
SWAPREL=$BASE/swap-releases   # one folder per llama-swap release: swap-releases/v275/llama-swap
IMAGE=localhost/llama-builder:cuda12.9
SERVICE=media-llama-swap.service
TEST_MODEL=qwen3.8-27b        # must load and answer after an update, or the update is rolled back
KEEP=3                        # old builds kept for manual rollback
OWNER=user
FORCE=0; [ "${1:-}" = "--force" ] && FORCE=1

log() { echo "$(date '+%F %T') $*"; }
exec 9>/run/media-llama-update.lock
flock -n 9 || { log "another update is running"; exit 1; }

gh_json() { curl -fsSL --retry 3 -H "Accept: application/vnd.github+json" "https://api.github.com/repos/$1"; }

# One-time migration: the original install had bin/ and llama-swap as plain files; make them symlinks into releases.
mkdir -p "$REL" "$SWAPREL"
if [ -d "$BASE/bin" ] && [ ! -L "$BASE/bin" ]; then
  log "migrating $BASE/bin -> $REL/legacy"
  mv "$BASE/bin" "$REL/legacy"; ln -sfn "$REL/legacy" "$BASE/bin"
fi
if [ -f "$BASE/llama-swap" ] && [ ! -L "$BASE/llama-swap" ]; then
  log "migrating $BASE/llama-swap -> $SWAPREL/legacy"
  mkdir -p "$SWAPREL/legacy"; mv "$BASE/llama-swap" "$SWAPREL/legacy/llama-swap"
  ln -sfn "$SWAPREL/legacy/llama-swap" "$BASE/llama-swap"
fi

OLD_BIN=$(readlink -f "$BASE/bin"); OLD_SWAP=$(readlink -f "$BASE/llama-swap")

# ---- llama.cpp -------------------------------------------------------------------------------------------
TAG=$(gh_json "ggml-org/llama.cpp/releases?per_page=1" | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["tag_name"])')
NEW_BIN=$REL/$TAG
if [ -x "$NEW_BIN/llama-server" ] && [ $FORCE = 0 ]; then
  log "llama.cpp $TAG already built"
else
  log "building llama.cpp $TAG for sm_70"
  podman image exists "$IMAGE" || podman build -t "$IMAGE" -f "$BASE/Containerfile.build" "$BASE"
  WORK=$(mktemp -d /var/tmp/llama-build.XXXXXX)
  BUILDLOG=/var/log/media-llama-build.log
  # on any failure, keep the compiler output (cmake.log + build.log) in $BUILDLOG before the work folder goes
  trap 'cat "$WORK"/cmake.log "$WORK"/build.log > "$BUILDLOG" 2>/dev/null; log "build failed, see $BUILDLOG"; rm -rf "$WORK"' EXIT
  podman run --rm -v "$WORK:/work:Z" "$IMAGE" bash -euc "
    git clone -q --depth 1 --branch '$TAG' https://github.com/ggml-org/llama.cpp /work/src
    cmake -S /work/src -B /work/build -G Ninja -DCMAKE_BUILD_TYPE=Release \
      -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=70 -DGGML_NATIVE=ON \
      -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_CURL=OFF \
      -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON -DCMAKE_INSTALL_RPATH='\$ORIGIN' \
      -DCMAKE_EXE_LINKER_FLAGS=-Wl,--allow-shlib-undefined > /work/cmake.log 2>&1
    # ^ the container has no GPU driver, so libcuda (cuGetErrorString & co) is resolved at run time by the VM's driver,
    #   the same way llama.cpp's own Docker images are built
    cmake --build /work/build -j \$(nproc) --target llama-server llama-bench > /work/build.log 2>&1
    mkdir -p /work/out
    cp -a /work/build/bin/llama-server /work/build/bin/llama-bench /work/out/
    find /work/build -name 'lib*.so*' -exec cp -a {} /work/out/ \;
    cp -a /usr/local/cuda/lib64/libcudart.so.12* /usr/local/cuda/lib64/libcublas.so.12* /usr/local/cuda/lib64/libcublasLt.so.12* /work/out/
    cp -a /usr/lib/x86_64-linux-gnu/libgomp.so.1* /work/out/
    cp -a /usr/lib/x86_64-linux-gnu/libnccl.so.2* /work/out/ 2>/dev/null || true
  "
  rm -rf "$NEW_BIN.tmp"; mv "$WORK/out" "$NEW_BIN.tmp"
  LD_LIBRARY_PATH="$NEW_BIN.tmp" "$NEW_BIN.tmp/llama-server" --version >/dev/null 2>&1 \
    || { log "new llama-server does not start; keeping $OLD_BIN"; rm -rf "$NEW_BIN.tmp"; exit 1; }
  rm -rf "$NEW_BIN"; mv "$NEW_BIN.tmp" "$NEW_BIN"
  trap - EXIT; rm -rf "$WORK"
fi

# ---- llama-swap ------------------------------------------------------------------------------------------
read -r SWAPTAG SWAPURL < <(gh_json "mostlygeek/llama-swap/releases/latest" | python3 -c '
import json,sys; d=json.load(sys.stdin)
a=[x["browser_download_url"] for x in d["assets"] if x["name"].endswith("_linux_amd64.tar.gz")][0]
print(d["tag_name"], a)')
NEW_SWAP=$SWAPREL/$SWAPTAG/llama-swap
if [ ! -x "$NEW_SWAP" ]; then
  log "downloading llama-swap $SWAPTAG"
  mkdir -p "$SWAPREL/$SWAPTAG.tmp"
  curl -fsSL --retry 3 "$SWAPURL" | tar -xz -C "$SWAPREL/$SWAPTAG.tmp" llama-swap
  "$SWAPREL/$SWAPTAG.tmp/llama-swap" --version >/dev/null
  rm -rf "$SWAPREL/$SWAPTAG"; mv "$SWAPREL/$SWAPTAG.tmp" "$SWAPREL/$SWAPTAG"
fi

chown -R "$OWNER:$OWNER" "$REL" "$SWAPREL"

if [ "$(readlink -f "$NEW_BIN")" = "$OLD_BIN" ] && [ "$(readlink -f "$NEW_SWAP")" = "$OLD_SWAP" ]; then
  log "already current: llama.cpp $TAG, llama-swap $SWAPTAG"; exit 0
fi

# ---- switch, test, roll back if needed --------------------------------------------------------------------
verify() {
  for _ in $(seq 60); do curl -fsS -m 5 http://127.0.0.1:8086/v1/models >/dev/null 2>&1 && break; sleep 2; done
  curl -fsS -m 900 http://127.0.0.1:8086/v1/chat/completions -H 'Content-Type: application/json' \
    -d "{\"model\":\"$TEST_MODEL\",\"max_tokens\":512,\"messages\":[{\"role\":\"user\",\"content\":\"Reply with the single word: ready\"}]}" \
  | python3 -c 'import json,sys; m=json.load(sys.stdin)["choices"][0]["message"]; sys.exit(0 if (m.get("content") or m.get("reasoning_content")) else 1)'
}

log "switching: llama.cpp $(basename "$OLD_BIN") -> $TAG, llama-swap $(basename "$(dirname "$OLD_SWAP")") -> $SWAPTAG"
ln -sfn "$NEW_BIN" "$BASE/bin"; ln -sfn "$NEW_SWAP" "$BASE/llama-swap"
systemctl restart "$SERVICE"
if verify; then
  log "ok: $TEST_MODEL answers on llama.cpp $TAG / llama-swap $SWAPTAG"
  echo "llama.cpp=$TAG llama-swap=$SWAPTAG updated=$(date -Is)" > "$BASE/CURRENT"
else
  log "FAILED: $TEST_MODEL did not answer; rolling back"
  journalctl -u "$SERVICE" --since "-20min" --no-pager | tail -40
  ln -sfn "$OLD_BIN" "$BASE/bin"; ln -sfn "$OLD_SWAP" "$BASE/llama-swap"
  systemctl restart "$SERVICE"
  verify && log "rolled back and working" || log "rolled back, but the old version does not answer either"
  exit 1
fi

# ---- prune old builds (never the current one) -------------------------------------------------------------
prune() { # $1 = dir, $2 = current target dir
  ls -1dt "$1"/*/ 2>/dev/null | sed 's:/$::' | grep -vx "$2" | grep -v '\.tmp$' | tail -n +$((KEEP)) | while read -r d; do
    log "removing old $(basename "$d")"; rm -rf "$d"
  done
}
prune "$REL" "$(readlink -f "$BASE/bin")"
prune "$SWAPREL" "$(dirname "$(readlink -f "$BASE/llama-swap")")"
