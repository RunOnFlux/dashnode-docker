#!/usr/bin/env bash
# Non-fatal health check: passes as long as the daemon responds. Reports smartnode
# service/PoSe status to the log but never fails on a stale service/PoSe ban
# (relocation would not fix registration; mn-autoheal.sh repairs it in place).
# shellcheck disable=SC1091
source /usr/local/bin/coin.env

H=$($CLI getblockcount 2>/dev/null)
if ! [[ "$H" =~ ^[0-9]+$ ]]; then
    echo "Daemon not responding..." >> /proc/1/fd/1
    exit 1
fi

if [[ -n "${PROTXHASH:-}" ]]; then
    INFO=$($CLI protx info "$PROTXHASH" 2>/dev/null)
    if [[ -n "$INFO" ]]; then
        SVC=$(echo "$INFO" | jq -r '.state.service // "unknown"')
        POSE=$(echo "$INFO" | jq -r '.state.PoSeBanHeight // -1')
        echo "SN service=${SVC} desired=${FLUX_NODE_HOST_IP:-unknown}:${MN_PORT} PoSeBanHeight=${POSE}" >> /proc/1/fd/1
    fi
fi

echo "Daemon healthy (height ${H})" >> /proc/1/fd/1
