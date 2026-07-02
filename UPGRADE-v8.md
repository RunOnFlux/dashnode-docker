# DashMN → Flux v8 upgrade

Makes the Dash masternode app on Flux robust instead of best-effort. Fixes five
defects in the legacy v4 app + image.

## What was broken (legacy v4)

| # | Defect | Consequence |
|---|--------|-------------|
| 1 | App forced to **3 instances**, but a masternode is **one** on-chain identity | 2 of 3 paid containers are dead weight; no masternode-uptime redundancy |
| 2 | **No static IP** — containers relocatable across arbitrary nodes | any move changes the IP → PoSe ban |
| 3 | Advertised **port 37500** (legacy Flux port range) | mainnet Dash masternodes must use **9999**; non-standard ports are penalised by the network |
| 4 | `externalip` written **once** from a 3rd-party IP-echo; `FLUX_NODE_HOST_IP` ignored | stale advertised address after any restart/relocation |
| 5 | **No on-chain self-healing** (no ProUpServTx) | recovery from a PoSe ban is fully manual |

## What changed

### Marketplace spec — `dashmn-v8.marketplace.json`
Replaces the `DashMN` entry in `RunOnFlux/fluxstats/config/marketplaceApps.json`.
- `version: 8`, `instances: 2` (HA — see failover section). Both instances receive the
  same `KEY` + `PROTXHASH`; the autoheal controller ensures only one is the active
  (registered) masternode at a time.
- `staticip: true` — FluxOS only schedules the app on nodes with a **verified stable
  public IP**, and if that node's IP ever changes it redeploys the app elsewhere
  (never runs on a silently-wrong IP).
- `ports: [9999]`, `containerPorts: [9999]` — correct mainnet port (legal now that the
  Flux app-port range is 1-65535; 9999 is not banned).
- Adds a `PROTXHASH` user input alongside `KEY` to enable auto self-healing.
- Resources raised to cpu 2 / ram 4000 / hdd 70 for reliable sync + headroom.

### Image
- **`node_initialize.sh`** — prefers `FLUX_NODE_HOST_IP`; advertises `IP:9999`;
  re-asserts `externalip` and the operator key on **every** boot.
- **`mn-autoheal.sh`** (new, runs under supervisor) — the HA controller. Every cycle
  (default 120s) it reads the on-chain `service`/`PoSeBanHeight` (`protx info`), and:
  keeps the registration in sync with `FLUX_NODE_HOST_IP:9999`; revives itself if
  PoSe-banned; and runs **leader election** across the app's instances (discovered via
  the Flux `/apps/location` API) so exactly one instance holds the registration and a
  survivor takes over (via **ProUpServTx**) when the leader dies. Unit-tested across the
  registered/standby/leader-down/deferral/syncing/banned branches.
- **`check-health.sh`** — logs on-chain service + PoSe status (non-fatal, so it never
  triggers pointless relocation).
- **`Dockerfile` / `supervisord.conf`** — ship & run the autoheal watcher.

## Security model (unchanged trust boundary)
Only the **operator BLS key** lives in the container — it can update service metadata
and sign consensus messages, but **cannot move the 1000 DASH collateral** (that needs
the owner key, which stays in the user's wallet). The autoheal watcher additionally
needs a **tiny DASH fee balance** to broadcast ProUpServTx; the fee-source address is
printed to the container log on startup — fund it once with ~0.01 DASH (covers
thousands of updates). Worst case if the container is compromised: an attacker gets the
operator key (already true today) + the dust fee balance.

## Deploy flow for the user
1. Send **1000 DASH** collateral to your own wallet address (never leaves your wallet).
2. Register the masternode (`protx register_prepare/submit`) from your wallet, using
   `<will-be-assigned-Flux-IP>:9999` — or register, note the `proTxHash`, and let the
   container's autoheal set the correct service on first run.
3. Deploy `DashMN` on Flux, providing `KEY` (operator BLS priv) and `PROTXHASH`.
4. Fund the printed fee-source address with ~0.01 DASH (one time).
5. The node keeps its own service registration correct across any relocation.

## Failover, bootstrap & why NOT to syncthing-share the chain

A masternode is a **single on-chain identity** — only one IP:port can be the
registered service at a time — so classic N-replica redundancy doesn't map directly.

**Do NOT use Flux's containerData sync flags (`s`/`g`/`r`) on the chain dir:**
- Syncthing does file-level eventual sync; a live LevelDB chain (blocks/chainstate)
  written by dashd would corrupt.
- Flux's sync state machine can **stop the container** during sync and even **delete
  the mount data** to re-seed from a master — the opposite of always-on.
- There is nothing else worth syncing: the identity is just `KEY` + `PROTXHASH` (env).

**Fast failover = bootstrap, not sync.** Each instance keeps its own independent
chain; a fresh volume (first deploy or relocation to a new node) fetches a recent
snapshot and catches up in minutes:
- `BOOTSTRAP_URL`  — tar.gz of a recent `.dashcore` (blocks/chainstate/evodb/llmq).
- `BOOTSTRAP_SHA256` (optional) — integrity check.
- RunOnFlux should host + refresh this snapshot (Flux Storage / CDN) and set
  `BOOTSTRAP_URL` in the marketplace entry's `environmentParameters`.

### Why HA (2 instances), not single-instance

A single instance is **not** viable: when its node dies, FluxOS keeps counting the
dead instance as "running" for up to **`RUNNING_EXPIRY_MS = 125 min`** (`appConstants.js`)
before it even redeploys — a ~2-hour gap that exceeds Dash's PoSe tolerance (~2 DKG
failures per payment cycle) and costs the payment slot. So **DashMN ships as 2-instance
HA** (`instances: 2`, ~2× price):
- Both instances stay at chain tip on their **OWN** chains (never syncthing-share a live
  DB — that stops the container / risks wiping data; see below).
- Only the leader holds the registration; the standby is warm and ready.
- On leader death the elected survivor is already synced and re-points the registration
  to itself within one cycle → failover in **minutes, not hours**. No forced failback.
- Bootstrap still matters for a fresh instance's first sync.

## Rollout note
v8 single-instance + staticip narrows the placement pool to static-IP nodes (still
plentiful — Hetzner/OVH/Contabo/etc.) in exchange for a masternode that actually stays
ENABLED. Roll a new `runonflux/dashnode:latest` image, then update the marketplace entry.
This same pattern is the correct template for any future masternode coin (e.g. Beldex).
