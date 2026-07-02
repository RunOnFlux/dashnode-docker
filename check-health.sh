#!/usr/bin/env bash
function max(){

    m="0"
    for n in "$@"
    do        
        if egrep -o "^[0-9]+$" <<< "$n" &>/dev/null; then
            [ "$n" -gt "$m" ] && m="$n"
        fi
    done
    
    echo "$m"
    
}

NETWORK=(
"$(curl -SsL https://chainz.cryptoid.info/dash/api.dws?q=getblockcount)"
"$(curl -SsL https://explorer.dash.org/insight-api//status?q=getInfo | jq .info.blocks)"
)

CURRENT_NODE_HEIGHT=$(dash-cli -getinfo | jq '.blocks')
if ! egrep -o "^[0-9]+$" <<< "$CURRENT_NODE_HEIGHT" &>/dev/null; then
  echo "Daemon not working correct..."
  echo "Daemon not working correct..." >> /proc/1/fd/1
  exit 1
fi

# Non-fatal masternode status report (visible in `docker logs`). We intentionally
# do NOT fail the healthcheck on a stale service/PoSe ban: relocation would not
# fix registration and could cause churn — mn-autoheal.sh repairs it in place.
if [[ -n "${PROTXHASH:-}" ]]; then
  MN_INFO=$(dash-cli protx info "$PROTXHASH" 2>/dev/null)
  if [[ -n "$MN_INFO" ]]; then
    MN_SERVICE=$(echo "$MN_INFO" | jq -r '.state.service // "unknown"')
    MN_POSE=$(echo "$MN_INFO" | jq -r '.state.PoSeBanHeight // -1')
    DESIRED_SERVICE="${FLUX_NODE_HOST_IP:-unknown}:9999"
    echo "MN service on-chain=${MN_SERVICE} desired=${DESIRED_SERVICE} PoSeBanHeight=${MN_POSE}" >> /proc/1/fd/1
  fi
fi

NETWORK_BLOCK_HEIGHT=$(max ${NETWORK[*]})
if egrep -o "^[0-9]+$" <<< "$NETWORK_BLOCK_HEIGHT" &>/dev/null; then
  DIFF=$((NETWORK_BLOCK_HEIGHT-CURRENT_NODE_HEIGHT))
  DIFF=${DIFF#-}
else
  echo "Daemon working but check cant veryfity sync with network..."
  echo "Daemon working but check cant veryfity sync with network..." >> /proc/1/fd/1
  exit
fi

if [[ "$DIFF" -le 10 ]]; then
 echo "Daemon working and is synced with network (block height: $CURRENT_NODE_HEIGHT)"
 echo "Daemon working and is synced with network (block height: $CURRENT_NODE_HEIGHT)" >> /proc/1/fd/1
else
 echo "Daemon working but is not synced with network (block height: $NETWORK_BLOCK_HEIGHT/$CURRENT_NODE_HEIGHT, left: $DIFF)"
 echo "Daemon working but is not synced with network (block height: $NETWORK_BLOCK_HEIGHT/$CURRENT_NODE_HEIGHT, left: $DIFF)" >> /proc/1/fd/1
 exit 1
fi
