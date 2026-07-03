#!/usr/bin/env bash
# Generic Flux HA masternode initializer. Coin-specific values live in coin.env.
#  - prefer the Flux-injected FLUX_NODE_HOST_IP (stable when staticip:true)
#  - advertise the correct mainnet MN port in externalip
#  - re-assert externalip and the operator BLS key on EVERY boot (relocation-safe)
set -uo pipefail
# shellcheck disable=SC1091
source /usr/local/bin/coin.env

url_array=(
    "https://api4.my-ip.io/ip"
    "https://checkip.amazonaws.com"
    "https://api.ipify.org"
)
get_ip_fallback() {
    for url in "${url_array[@]}"; do
        WANIP=$(curl --silent -m 15 "$url" | tr -dc '[:alnum:].')
        [[ "$WANIP" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] && return 0
    done
    WANIP=""; return 1
}

if [[ -n "${FLUX_NODE_HOST_IP:-}" ]]; then
    WANIP="${FLUX_NODE_HOST_IP}"
    echo " Using Flux-injected node IP: ${WANIP}"
else
    echo " FLUX_NODE_HOST_IP not set; falling back to external IP lookup..."
    get_ip_fallback || echo " WARNING: could not determine external IP"
fi

mkdir -p "$DATADIR"

# First boot only: base config (rpc creds persist on the volume).
if [[ ! -f "$CONF" ]]; then
    {
        echo "rpcuser=$(pwgen -1 18 -n)"
        echo "rpcpassword=$(pwgen -1 20 -n)"
        echo "rpcallowip=127.0.0.1"
        echo "rpcbind=127.0.0.1"
        echo "server=1"
        echo "listen=1"
        echo "daemon=1"
        for n in ${SEED_NODES:-}; do echo "addnode=$n"; done
        [[ -n "${EXTRA_CONF:-}" ]] && printf '%s\n' "${EXTRA_CONF}"
    } >> "$CONF"
fi

# Always (re)assert the operator BLS key from KEY (supports rotation).
sed -i "/^${BLS_PARAM}=/d" "$CONF"
[[ -n "${KEY:-}" ]] && echo "${BLS_PARAM}=$KEY" >> "$CONF"

# Always refresh externalip to the CURRENT node IP:port (correct mainnet MN port).
sed -i "/^externalip=/d" "$CONF"
if [[ -n "${WANIP:-}" ]]; then
    echo "externalip=${WANIP}:${MN_PORT}" >> "$CONF"
    echo " externalip set to ${WANIP}:${MN_PORT}"
fi

# Optional fast-sync bootstrap. On a FRESH datadir (first deploy, or relocation to a
# new node), fetch a recent chain snapshot so we catch up in minutes instead of from
# genesis. Each instance keeps its OWN chain — we never syncthing-share a live DB.
# tar xf auto-detects gz/xz/bz2. Set BOOTSTRAP_URL (+ optional BOOTSTRAP_SHA256).
if [[ -n "${BOOTSTRAP_URL:-}" && ! -d "${DATADIR}/blocks" ]]; then
    echo " No local chain; fetching bootstrap: ${BOOTSTRAP_URL}"
    if curl -fSL -m 3600 "${BOOTSTRAP_URL}" -o /tmp/bootstrap.archive; then
        if [[ -z "${BOOTSTRAP_SHA256:-}" ]] || echo "${BOOTSTRAP_SHA256}  /tmp/bootstrap.archive" | sha256sum -c -; then
            if tar xf /tmp/bootstrap.archive -C "${DATADIR}"; then
                echo " Bootstrap extracted; daemon will sync the remaining gap."
            else
                echo " WARNING: bootstrap extract failed; syncing normally."
            fi
        else
            echo " WARNING: bootstrap checksum mismatch; ignoring snapshot, syncing normally."
        fi
        rm -f /tmp/bootstrap.archive
    else
        echo " WARNING: bootstrap download failed; syncing normally."
    fi
fi

# Keep the daemon alive.
while true; do
    if [[ -z "$(pgrep -x "${COIN_DAEMON}")" ]]; then
        echo " Starting ${COIN_DAEMON}..."
        ${COIN_DAEMON} -datadir="${DATADIR}" -conf="${CONF}" -daemon
    fi
    sleep 120
done
