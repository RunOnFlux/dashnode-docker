#!/usr/bin/env bash
# Dash masternode initializer for Flux.
#
# Key differences vs the legacy script:
#  - Prefers the Flux-injected FLUX_NODE_HOST_IP (stable when the app is deployed
#    with staticip:true) instead of third-party IP-echo services.
#  - Advertises the correct MAINNET masternode port (9999) in externalip.
#  - Re-asserts externalip and the operator key on EVERY boot, so a relocation /
#    restart never leaves a stale advertised address behind.
set -uo pipefail

CONFIG_FILE="/root/.dashcore/dash.conf"
MN_PORT=9999

# Fallback IP-echo services (used only if Flux did not inject FLUX_NODE_HOST_IP).
url_array=(
    "https://api4.my-ip.io/ip"
    "https://checkip.amazonaws.com"
    "https://api.ipify.org"
)

get_ip_fallback() {
    for url in "${url_array[@]}"; do
        WANIP=$(curl --silent -m 15 "$url" | tr -dc '[:alnum:].')
        if [[ "$WANIP" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
            return 0
        fi
    done
    WANIP=""
    return 1
}

# Prefer the IP that FluxOS injects for this node. With staticip:true this is a
# verified, stable public IP; on relocation FluxOS re-injects the new node's IP.
if [[ -n "${FLUX_NODE_HOST_IP:-}" ]]; then
    WANIP="${FLUX_NODE_HOST_IP}"
    echo " Using Flux-injected node IP: ${WANIP}"
else
    echo " FLUX_NODE_HOST_IP not set; falling back to external IP lookup..."
    get_ip_fallback || echo " WARNING: could not determine external IP"
fi

# First boot only: create the base config. RPC creds persist on the volume.
if [[ ! -f "$CONFIG_FILE" ]]; then
    RPCUSER=$(pwgen -1 18 -n)
    PASSWORD=$(pwgen -1 20 -n)
    {
        echo "rpcuser=$RPCUSER"
        echo "rpcpassword=$PASSWORD"
        echo "rpcallowip=127.0.0.1"
        echo "server=1"
        echo "daemon=1"
        echo "listen=1"
        echo "maxconnections=256"
    } >> "$CONFIG_FILE"
fi

# Always (re)assert the operator BLS key from the KEY env (supports key rotation).
sed -i "/^masternodeblsprivkey=/d" "$CONFIG_FILE"
if [[ -n "${KEY:-}" ]]; then
    echo "masternodeblsprivkey=$KEY" >> "$CONFIG_FILE"
fi

# Always refresh externalip to the CURRENT node IP:port. Mainnet masternodes must
# advertise port 9999 — non-standard ports are penalised by the Dash network.
sed -i "/^externalip=/d" "$CONFIG_FILE"
if [[ -n "${WANIP:-}" ]]; then
    echo "externalip=${WANIP}:${MN_PORT}" >> "$CONFIG_FILE"
    echo " externalip set to ${WANIP}:${MN_PORT}"
fi

# Optional fast-sync bootstrap. On a FRESH volume (first deploy, or a relocation to
# a new node where the local volume does not follow) this fetches a recent chain
# snapshot so we catch up in minutes instead of syncing from genesis. This is the
# safe way to get fast failover: each instance keeps its OWN independent chain — we
# never syncthing-share a live database (that stops the container / risks wiping it).
if [[ -n "${BOOTSTRAP_URL:-}" && ! -d /root/.dashcore/blocks ]]; then
    echo " No local chain found; fetching bootstrap snapshot from ${BOOTSTRAP_URL}..."
    if curl -fSL -m 3600 "$BOOTSTRAP_URL" -o /tmp/bootstrap.tar.gz; then
        if [[ -z "${BOOTSTRAP_SHA256:-}" ]] || echo "${BOOTSTRAP_SHA256}  /tmp/bootstrap.tar.gz" | sha256sum -c -; then
            tar xzf /tmp/bootstrap.tar.gz -C /root/.dashcore && echo " Bootstrap extracted; dashd will sync the remaining gap."
        else
            echo " WARNING: bootstrap checksum mismatch — ignoring snapshot, syncing normally."
        fi
        rm -f /tmp/bootstrap.tar.gz
    else
        echo " WARNING: bootstrap download failed — syncing normally."
    fi
fi

# Keep dashd alive.
while true; do
    if [[ -z "$(pgrep dashd)" ]]; then
        echo " Starting dashd..."
        dashd -daemon
    fi
    sleep 120
done
