#!/usr/bin/env bash
# HA self-healing controller for a Dash masternode on Flux (Tier 2).
#
# Model: N instances (default 2), each a full dashd on its OWN independent chain.
# A masternode is a single on-chain identity, so only the LEADER (lowest-IP alive
# instance) holds the registration; the others are warm standbys. On leader death
# the elected survivor points the registration at itself via ProUpServTx. Failback
# is not forced (avoids churn). Standbys are not the registered service, so they do
# not participate in quorums — no double-signing risk.
#
# REQUIRES:
#   PROTXHASH  - masternode registration hash (proTxHash).  user-provided
#   KEY        - operator BLS private key.                  user-provided
#   A small DASH fee balance in the wallet (fund the printed address once).
# Injected by Flux: FLUX_NODE_HOST_IP (this node's public IP), FLUX_APP_NAME.
set -uo pipefail

MN_PORT=9999
CLI="${CLI:-dash-cli}"
CHECK_INTERVAL="${AUTOHEAL_INTERVAL:-120}"      # seconds between cycles (fast failover)
SETTLE="${AUTOHEAL_SETTLE:-5}"                  # settle window before promotion
FLUX_API="${FLUX_API:-https://api.runonflux.io}"
FEE_ADDR_FILE="/root/.dashcore/.mn_fee_address"

MYIP="${FLUX_NODE_HOST_IP:-}"
DESIRED="${MYIP}:${MN_PORT}"

log() { echo " [mn-autoheal] $*"; }

# ---- helpers (overridable in tests) ----------------------------------------

# TCP reachability probe (bash builtin, no extra deps).
probe() { timeout 5 bash -c "exec 3<>/dev/tcp/$1/$2" >/dev/null 2>&1; }

# Fully synced (not in initial block download)?
is_synced() {
    local ibd
    ibd=$($CLI getblockchaininfo 2>/dev/null | jq -r '.initialblockdownload // "true"')
    [[ "$ibd" == "false" ]]
}

# Discover sibling instance IPs for this app via the Flux location API.
# Falls back to stripping a compose component prefix if the first lookup is empty.
get_siblings() {
    local name="$1" ips
    ips=$(curl -s -m 15 "${FLUX_API}/apps/location/${name}" 2>/dev/null \
          | jq -r '.data[]?.ip // empty' 2>/dev/null | sed 's/:.*//' | grep -E '^[0-9.]+$' | sort -u)
    if [[ -z "$ips" && "$name" == *_* ]]; then
        ips=$(curl -s -m 15 "${FLUX_API}/apps/location/${name#*_}" 2>/dev/null \
              | jq -r '.data[]?.ip // empty' 2>/dev/null | sed 's/:.*//' | grep -E '^[0-9.]+$' | sort -u)
    fi
    echo "$ips"
}

# Broadcast a ProUpServTx pointing the masternode at DESIRED (this instance).
promote() {
    local bal
    bal=$($CLI getbalance 2>/dev/null || echo 0)
    if awk "BEGIN{exit !(${bal:-0} <= 0)}"; then
        log "WARNING: wallet balance ${bal} DASH — cannot pay fee. Fund ${FEE_ADDR:-<addr>} with ~0.01 DASH."
        return 1
    fi
    if $CLI protx update_service "$PROTXHASH" "$DESIRED" "$KEY" >/dev/null 2>&1; then
        log "PROMOTED: ProUpServTx broadcast (update_service). service -> ${DESIRED}"
    elif $CLI protx update_service_legacy "$PROTXHASH" "$DESIRED" "$KEY" >/dev/null 2>&1; then
        log "PROMOTED: ProUpServTx broadcast (update_service_legacy). service -> ${DESIRED}"
    else
        log "ERROR: ProUpServTx failed (operator key scheme / PROTXHASH / balance?)."
        return 1
    fi
}

# ---- one control cycle (return, not continue, so it is unit-testable) -------
run_cycle() {
    [[ -z "${PROTXHASH:-}" || -z "${KEY:-}" || -z "$MYIP" ]] && return 0

    local INFO REGISTERED POSE reg_ip banned reg_alive SIBLINGS LEADER_ELECT RECHECK rc_ip
    INFO=$($CLI protx info "$PROTXHASH" 2>/dev/null || true)
    [[ -z "$INFO" ]] && { log "protx info failed for ${PROTXHASH} (registered yet?)"; return 0; }
    REGISTERED=$(echo "$INFO" | jq -r '.state.service // empty')
    POSE=$(echo "$INFO" | jq -r '.state.PoSeBanHeight // -1')
    reg_ip="${REGISTERED%%:*}"
    banned=false; [[ -n "$POSE" && "$POSE" != "-1" ]] && banned=true

    # Case 1: I am the registered masternode.
    if [[ "$REGISTERED" == "$DESIRED" ]]; then
        if $banned && is_synced; then
            log "I am registered but PoSe-banned (height ${POSE}); reviving."
            promote
        else
            log "active leader = me (${DESIRED}); PoSe ok."
        fi
        return 0
    fi

    # Is the currently-registered leader alive & healthy?
    reg_alive=false
    if [[ -n "$reg_ip" ]]; then
        if [[ "$reg_ip" == "$MYIP" ]]; then is_synced && reg_alive=true
        else probe "$reg_ip" "$MN_PORT" && reg_alive=true; fi
    fi
    if $reg_alive && ! $banned; then
        log "standby: leader ${REGISTERED} healthy."
        return 0
    fi

    # Case 2: leader down / stale / banned -> elect a survivor.
    if ! is_synced; then log "leader unhealthy but I'm still syncing; wait."; return 0; fi

    SIBLINGS=$(get_siblings "${FLUX_APP_NAME:-}")
    local alive=("$MYIP") ip
    for ip in $SIBLINGS; do
        [[ "$ip" == "$MYIP" ]] && continue
        probe "$ip" "$MN_PORT" && alive+=("$ip")
    done
    LEADER_ELECT=$(printf '%s\n' "${alive[@]}" | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n | head -1)

    if [[ "$MYIP" != "$LEADER_ELECT" ]]; then
        log "leader down; deferring to elected survivor ${LEADER_ELECT}."
        return 0
    fi

    # I am the elected survivor. Brief settle, then re-check nobody healthy took over.
    sleep "$SETTLE"
    RECHECK=$($CLI protx info "$PROTXHASH" 2>/dev/null | jq -r '.state.service // empty')
    if [[ -n "$RECHECK" && "$RECHECK" != "$REGISTERED" && "$RECHECK" != "$DESIRED" ]]; then
        rc_ip="${RECHECK%%:*}"
        if probe "$rc_ip" "$MN_PORT"; then log "another survivor (${RECHECK}) already took over; standing down."; return 0; fi
    fi
    log "elected survivor = me; leader ${REGISTERED:-<none>} is down -> taking over."
    promote
}

# ---- startup + loop --------------------------------------------------------
main() {
    until $CLI getblockchaininfo >/dev/null 2>&1; do log "waiting for dashd RPC..."; sleep 30; done

    if [[ -f "$FEE_ADDR_FILE" ]]; then
        FEE_ADDR=$(cat "$FEE_ADDR_FILE")
    else
        FEE_ADDR=$($CLI getnewaddress "mn-fee" 2>/dev/null || true)
        [[ -n "$FEE_ADDR" ]] && echo "$FEE_ADDR" > "$FEE_ADDR_FILE"
    fi
    log "this instance IP: ${MYIP:-unknown} | fee-source (fund ~0.01 DASH once): ${FEE_ADDR:-unavailable}"
    [[ -z "${PROTXHASH:-}" ]] && log "PROTXHASH not set — HA/self-heal DISABLED."

    while true; do
        sleep "$CHECK_INTERVAL"
        run_cycle
    done
}

# Allow tests to source helpers/run_cycle without launching the loop.
[[ "${AUTOHEAL_SOURCE_ONLY:-}" == "1" ]] || main
