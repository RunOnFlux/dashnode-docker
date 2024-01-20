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
