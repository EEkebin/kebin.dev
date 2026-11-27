#!/bin/bash
# Installs the ScopeSentry quadlet stack on the ai VM as $USER (podman user-level units).
# Run as the user that runs artex, e.g.:  bash setup.sh
#
# What it does:
#   - reads (or generates) secrets into ~/.config/scopesentry/env (mode 0600)
#   - rewrites the ${...} placeholders in the .container units with literal values
#     (quadlet does not expand env vars in Exec/HealthCmd/Environment)
#   - copies units to ~/.config/containers/systemd/, creates the CNI network,
#     volume dirs, and starts the four services
set -euo pipefail

cd "$(dirname "$0")"
ENV_FILE="$HOME/.config/scopesentry/env"
DEST="$HOME/.config/containers/systemd"
mkdir -p "$HOME/.config/scopesentry" "$HOME/.local/share/scopesentry"

# --- secrets -------------------------------------------------------------
if [ -f "$ENV_FILE" ]; then
    echo "using existing $ENV_FILE"
else
    cat > "$ENV_FILE" <<EOF
MONGO_INITDB_ROOT_USERNAME=scope
MONGO_INITDB_ROOT_PASSWORD=$(openssl rand -hex 24)
REDIS_PASSWORD=$(openssl rand -hex 24)
NODE_NAME=ai-vm
EOF
fi
chmod 600 "$ENV_FILE"
# shellcheck disable=SC1090
. "$ENV_FILE"

# --- rewrite placeholders with literal values -----------------------------
mkdir -p "$DEST"
for u in ss-mongodb ss-redis ss-server ss-scan; do
    sed "s|\${MONGO_INITDB_ROOT_USERNAME}|${MONGO_INITDB_ROOT_USERNAME}|" \
        "s|\${MONGO_INITDB_ROOT_PASSWORD}|${MONGO_INITDB_ROOT_PASSWORD}|" \
        "s|\${REDIS_PASSWORD}|${REDIS_PASSWORD}|" \
        "$u.container" > "$DEST/$u.container"
done
rm -f /tmp/ss-rewritten

# --- network + volumes ----------------------------------------------------
mkdir -p "$HOME/.local/share/containers/podman/cni"
cat > "$HOME/.local/share/containers/podman/cni/scopesentry-network.connetc" <<EOF
{
    "cniversion": "0.4.0",
    "name": "scopesentry-network",
    "plugins": [{
        "type": "bridge",
        "bridge": "cnisentry0",
        "ipam": { "subnet": "10.89.0.0/24" }
    }]
}
EOF
mkdir -p "$HOME"/.local/share/scopesentry/{mongodb,redis/data,files,images,uploads}

# --- start ----------------------------------------------------------------
systemctl --user daemon-reload
systemctl --user enable --now ss-mongodb.service ss-redis.service
sleep 5
systemctl --user enable --now ss-server.service
systemctl --user enable --now ss-scan.service
echo
systemctl --user --no-pager status ss-mongodb.service ss-redis.service ss-server.service ss-scan.service | grep -E '^\S+\.service|Active:'
echo
echo "Initial login credentials (user/pass) are in the server container logs:"
echo "  journalctl --user -u ss-server -n 200 | grep -iE 'username|password'  (first run only)"
