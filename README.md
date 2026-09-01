# Rubix Node — Docker

Run a **Rubix node** with one command. The image downloads the official
[`rubixgoplatform`](https://github.com/rubixchain/rubixgoplatform/releases) release
binary (no Go build), pairs it with its own Postgres + IPFS, and persists everything
so a reboot resumes cleanly. Built for exchanges, businesses, and anyone who wants to
run a node with minimal friction.

One tool does everything: **`./node.sh`** (`run.sh`, `stop.sh`, `status.sh` are
shortcuts for the common commands). For a **fleet** of nodes on one host there's
`./start_nodes.sh` and `./kill_nodes.sh`.

---

## 1. Requirements

- A Linux host (VM or server), amd64 or arm64
- **Docker + Docker Compose v2** — check with `docker compose version`
- `curl` (used to look up the latest release and to talk to the node API)
- `jq` — only for the fleet helper scripts in [section 9](#9-fleet-helper-scripts-dids-quorums-balances)
- Outbound internet (to reach the network's bootstrap peers + IPFS)
- ~2 GB RAM and a few GB disk per node to start

## 2. First-time setup

**a. Install Docker** (skip if you already have it):

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker "$USER"     # run docker without sudo
newgrp docker                       # apply the group to this shell (or log out/in)
```

Don't run these scripts with `sudo` once that's done — a root-created `data/` dir
makes every later non-root run fail on permissions.

**b. Get this folder onto the host** (copy it, or `git clone` your repo), then:

```bash
cd rubix-docker
chmod +x *.sh
./node.sh up
```

That's it. The first run builds the image (downloads the binary + IPFS) and
initialises the node — **1–2 minutes**. It auto-creates the node's config, so there's
nothing to edit. When it's ready:

```bash
./node.sh status        # ✓ Postgres / ✓ API / ✓ IPFS, peer id, DIDs, storage, cpu/mem
curl -s localhost:20000/api/ping
```

## 3. Running the node

```bash
./node.sh up                  # start the node (node 1)
./node.sh status              # health overview
./node.sh logs                # follow logs (Ctrl-C to detach)
./node.sh down                # stop, keep all data
./node.sh down --wipe         # stop and delete this node's data + its .env.node1
./node.sh ls                  # list running node stacks
```

Set anything from the command line — each flag is saved to `.env.nodeN`, so the node
keeps it next time:

```bash
./node.sh up --api-port 20005 --swarm-port 4010 --data-path /mnt/rubix-data
./node.sh up --network mainnet --version v1.0.1 --external-ip 203.0.113.7
```

| Flag | Default (node *N*) | Meaning |
|---|---|---|
| `--version <tag>` | **latest GitHub release** | `rubixgoplatform` release to run. Looked up from `rubixchain/rubixgoplatform` when the node is first created, then **pinned** in `.env.nodeN` |
| `--branch <ref>` | — | build from a git branch/tag/SHA instead of a release ([below](#build-from-a-source-branch-advanced)) |
| `--rebuild` | — | with a branch build: re-clone so new commits on that branch are picked up |
| `--network <mode>` | `testnet` | `testnet` / `mainnet` / `localnet` — fixed for the life of the data dir |
| `--api-port <port>` | `20000 + (N-1)` | host port for the node HTTP API (it always runs on 20000 *inside* the container — this is the port you connect to) |
| `--api-bind <ip>` | `127.0.0.1` | interface the API binds to. `0.0.0.0` only if a remote backend needs it (then firewall it — the API has no auth) |
| `--swarm-port <port>` | `4001 + (N-1)` | host port for the P2P/IPFS swarm — **must be reachable from the internet** |
| `--pg-port <port>` | `5433 + (N-1)` | Postgres host port (kept on localhost) |
| `--external-ip <ip>` | auto | public/LAN IP announced to the DHT (auto-detected via `api.ipify.org` if unset) |
| `--data-path <path>` | `./data/nodeN` | where node + DB data is stored (relative or absolute) |

`--wipe` is a flag of `down`, not `up`: `./node.sh down 2 --wipe`.

You never have to create or edit an env file — `node.sh` writes one per node
(`.env.nodeN`) for you. You *can* edit it directly if you prefer. (`.env.example` is
a reference listing every variable; it shows the compose fallbacks, not the
index-offset values `node.sh` writes.)

## 4. Running several nodes on one host

Each node is an index (1, 2, 3, …) and is fully isolated — its own containers, data
dir, and auto-offset ports:

```bash
./node.sh up 1        # API 20000, swarm 4001, pg 5433, data ./data/node1
./node.sh up 2        # API 20001, swarm 4002, pg 5434, data ./data/node2
./node.sh up 3        # API 20002, swarm 4003, pg 5435, data ./data/node3
./node.sh status 2    ./node.sh logs 2    ./node.sh down 2
./node.sh ls          # list all running node stacks
```

Override any default per node with the same flags. Each node needs its own **swarm
port opened inbound** (4001, 4002, 4003, …).

### Starting a whole fleet at once

`./start_nodes.sh` brings up **10 nodes** (by default) on a tidy port block —
**API 8000–8009**, **Postgres 9000–9009** — which is what the helper scripts in
[section 9](#9-fleet-helper-scripts-dids-quorums-balances) expect:

```bash
./start_nodes.sh                 # first run: creates them on TESTNET (the default)
./start_nodes.sh --mainnet       # first run: creates them on mainnet
./start_nodes.sh                 # later runs: each node starts on its stored network
./start_nodes.sh --nodes 4       # only nodes 1-4
./start_nodes.sh --version v1.0.4   # pin/change the release for every node
./start_nodes.sh --version latest   # move every node to the newest release
./start_nodes.sh --branch dev-x     # build every node from a git ref instead
./start_nodes.sh --rebuild          # re-clone: new commits on the branch they run
./kill_nodes.sh                  # stop them all (data kept)
./kill_nodes.sh --wipe           # stop AND delete every data dir + .env.nodeN
```

Rules worth knowing:

- **The network is decided once, at creation.** It's stored in `.env.nodeN` and reused
  on every later run — a plain `./start_nodes.sh` never changes it. Mainnet is never
  entered by accident: it takes an explicit `--mainnet`.
- **Switching an existing node's network is destructive.** Rubix refuses to reuse a
  data dir across networks, so the script stops and tells you rather than failing
  mid-boot. `./start_nodes.sh --mainnet --wipe-switch` deletes `./data/nodeN` first
  and re-creates the node — **DIDs, keys and tokens are gone**.
- **Versions are left alone** on existing nodes unless you pass `--version`, so
  branch-built nodes and deliberately pinned ones survive a plain restart.

## 5. Stopping, resuming, restarting & reboots

Your data (the node's **DID/keys**, token chains, IPFS repo, and Postgres) lives under
`DATA_PATH` (default `./data/nodeN`) as bind-mounts — it is **never** deleted by a
normal stop. Both containers run with `restart: unless-stopped`. So:

| Situation | What happens | What you do |
|---|---|---|
| The node process crashes | Docker **auto-restarts** it | nothing |
| The host **reboots** while the node was running | Docker **auto-starts** it on boot | nothing — verify with `./node.sh status` |
| You ran `./node.sh down` | containers are stopped/removed (data kept, `.env.nodeN` kept) | `./node.sh up` to resume — **same DID, same data** |
| You ran `./node.sh down --wipe` | containers stopped, **`./data/nodeN` and `.env.nodeN` deleted** | `./node.sh up` starts a brand-new node (back to default ports/network, since its env file is gone — use `./start_nodes.sh` to recreate a fleet node with its 8000-block port) |

In short: a node **resumes with the same identity** after a crash, reboot, or
`down` → `up`. The only way to lose data is `--wipe` (or deleting the data dir).

> Requires Docker to start on boot — it does by default on standard installs
> (`sudo systemctl enable docker` if yours doesn't).

## 6. Updating the node version

Versions are **pinned** — a node never changes version on a plain restart.

```bash
./update.sh              # check node 1, show current -> latest, ask before updating
./update.sh 2 5 7        # check several nodes
./update.sh --all        # check EVERY node here and update them in one command
./update.sh --all --yes  # same, no prompt (automation/cron)
./update.sh --check      # report versions only, change nothing
```

Branch builds have their own modes — `--branch <ref>`, `--rebuild`, `--release` — see
[Build from a source branch](#build-from-a-source-branch-advanced).

GitHub is queried once per run, however many nodes are checked. Nodes that are already
current, pinned *ahead* of the latest release, or built from a branch are reported and
left alone; if one node fails to rebuild the rest still get updated (the script exits
non-zero and names the failures).

Or pin a specific version yourself:

```bash
./node.sh up --version v1.0.1
```

Either way your data is untouched — only the binary is replaced.

### Build from a source branch (advanced)

By default a node runs the official **release binary**. To build from a
`rubixgoplatform` git **branch, tag, or commit** instead — e.g. to test a fix before
it's released — switch any node at any time. Node data is preserved; only the binary
changes:

```bash
./node.sh up 1 --branch development        # one node
./start_nodes.sh --branch development      # every node in the fleet
./update.sh --all --branch development     # same, via update.sh
```

The ref is remembered as `BUILD_BRANCH` in `.env.nodeN`, so every later restart
rebuilds from it (`node.sh` layers `docker-compose.branch.yml` automatically).

**Picking up new commits on that same branch needs `--rebuild`.** A plain restart
reuses Docker's cached `git clone` layer, so it would keep running the binary you
built the first time:

```bash
./update.sh --all --rebuild     # re-clone + recompile every branch-built node
./node.sh up 1 --rebuild        # just node 1
```

`--rebuild` changes the `BUILD_CACHEBUST` build arg, which invalidates the clone layer
in `Dockerfile.branch` and nothing before it. Across a fleet the whole run shares one
value, so the first node compiles and the rest reuse its layers.

Going back to a release binary clears the branch:

```bash
./update.sh --all --release     # every node -> latest release
./node.sh up 1 --version v1.0.5 # one node -> a specific release
```

In its default (release) mode `./update.sh` reports branch-built nodes and leaves them
alone — there's no release version to compare against.

| Want to… | Command |
|---|---|
| Put the fleet on a branch | `./update.sh --all --branch <ref>` |
| Pull new commits on that branch | `./update.sh --all --rebuild` |
| See what would change first | add `--check` |
| Go back to release binaries | `./update.sh --all --release` |
| Do any of the above for one node | replace `--all` with the index, e.g. `./update.sh 3 --branch <ref>` |

`--branch`, `--rebuild` and `--release` are mutually exclusive. Each mode surveys
every node and asks once before touching anything (`--yes` skips the prompt); if one
node fails to build the rest still proceed.

To build from a fork or a different main package path, override the `BUILD_REPO` /
`BUILD_PKG` / `GO_VERSION` build args in `Dockerfile.branch`.

## 7. Ports to open

Numbers below are for **node 1**; node *N* shifts each by *N-1*.

| Port | Direction | Open to | Why |
|---|---|---|---|
| **`SWARM_PORT` (4001) TCP** | **inbound** | **the internet** | **Required.** The libp2p/IPFS P2P port. The node announces `EXTERNAL_IP:SWARM_PORT`; peers and quorums dial it to reach you. **Port-forward it if behind NAT.** Without it the node can call out but can't be reliably dialled (receiving tokens, acting as quorum). |
| `API_PORT` (20000, or 8000 for a `start_nodes.sh` fleet) TCP | inbound | **trusted only** | HTTP API, **no authentication**. Keep on `127.0.0.1` (default) or restrict to your backend's IP. Never expose publicly. |
| `PG_PORT` (5433, or 9000 for a fleet) TCP | — | nobody | Postgres is bound to localhost; leave closed. |
| any | **outbound** | the internet | The node needs to reach bootstrap peers, IPFS, and `api.github.com` (release lookup). Usually already allowed. |

`ufw` example (open only the swarm ports publicly):

```bash
sudo ufw allow 4001/tcp        # SWARM_PORT for node 1 — 4002, 4003, ... for extra nodes
# expose the API only to a specific backend if needed:
# sudo ufw allow from <backend-ip> to any port 20000 proto tcp
```

## 8. First steps after the node is up

```bash
# create a DID (use a strong password — this is your node's key)
curl -s -X POST localhost:20000/rubix/v1/dids/create \
  -H 'Content-Type: application/json' -d '{"password":"<your-password>","childPath":0}'

# register it on the network — two steps:
#   1) POST .../register  -> returns {"result":{"id":"<id>"}, "message":"Password needed"}
#   2) POST /rubix/v1/signature with {id, password}
curl -s -X POST localhost:20000/rubix/v1/dids/<did>/register
curl -s -X POST localhost:20000/rubix/v1/signature \
  -H 'Content-Type: application/json' -d '{"id":"<id>","password":"<your-password>"}'
```

`./node.sh status` lists the DIDs the node holds at any time.

## 9. Fleet helper scripts (DIDs, quorums, balances)

These automate the calls above across a fleet. **They assume the `start_nodes.sh` port
block (API 8000–8009) and are hardcoded to those ten ports** — they won't find a node
started as plain `./node.sh up 1` on 20000. All of them need `jq`.

```bash
./create_dids.sh              # create one DID per node (ports 8000-8009) -> did_results.json
./register_dids.sh            # register every DID in did_results.json (register + signature)
./check_balances.sh           # balance table for every DID in did_results.json
./list_configed_quorum.sh     # show the quorum list each node has configured
./add_quorum.sh               # POST /quorums/add for every entry in quorum_did.json
./get_facuet_by_one_rbt.sh    # ask faucet.rubix.net for RBT for every DID (1s apart)
```

Notes:

- **`DID_PASSWORD` defaults to `mypassword`** in `create_dids.sh` and
  `register_dids.sh`. Set a real one — and the same one for both:
  `DID_PASSWORD='…' ./create_dids.sh`. This password protects the node's keys.
- `did_results.json` is written by `create_dids.sh` and read by all the others; it
  holds `{port, did, peer_id}` per node.
- `quorum_did.json` is **not generated** by any script — you create it yourself, as a
  JSON array of `{"port": 8000, "did": "…"}` objects listing the quorum DIDs to add.
- Both files are git-ignored, and hold identifiers for your nodes — keep them local.
- The faucet is a Rubix-hosted service for funding test DIDs; it isn't part of this
  repo and can be rate-limited or down.

## 10. Troubleshooting

- **Can't reach the API from another machine** → it's bound to `127.0.0.1` by design.
  Start with `--api-bind 0.0.0.0`, open the port to your backend only, and never to
  the public internet (no auth).
- **Public IP / peers can't reach the node** → open/forward `SWARM_PORT` inbound
  (firewall + router). Check `./node.sh status` → "connected peers".
- **Node container exits immediately** → `./node.sh logs`. A `network_mode` mismatch
  ("ERROR: Network mismatch. Existing=… New=…") means the data dir was created on a
  different network — wipe it (`./node.sh down 1 --wipe`, or
  `./start_nodes.sh --mainnet --wipe-switch` for the whole fleet) before switching.
- **`./start_nodes.sh` still starts testnet nodes after you edited a default** →
  defaults only apply to *new* nodes. An existing `.env.nodeN` wins; check it with
  `grep NETWORK_MODE .env.node1`.
- **Port already in use** → pick another with `--api-port` / `--swarm-port` /
  `--pg-port`, or run as a different node index.
- **Permission denied on `./data/nodeN`** → something was run with `sudo`. Fix with
  `sudo chown -R "$USER:$USER" .` and stop using sudo.
- **"couldn't reach GitHub for the latest release"** → offline or rate-limited. The
  scripts fall back to `FALLBACK_VERSION` in `common.sh`; pass `--version <tag>`
  explicitly to be sure of what you get.
- **Reset everything for this node** → `./node.sh down --wipe` then `./node.sh up`.
- **Changing the Postgres major version** (e.g. 16 → 18) is **not in-place** — a data
  dir created by the old version won't start under the new one. Just start fresh:
  `./node.sh down 1 --wipe` then `./node.sh up 1` (the node re-creates its DID and
  state on a clean Postgres 18).

## 11. Files in this folder

```
node.sh              # the one tool: up / down / logs / status / ls
run.sh stop.sh status.sh    # shortcuts for node.sh up / down / status
start_nodes.sh       # bring up a fleet (default 10 nodes, API 8000-8009)
kill_nodes.sh        # stop the fleet (--wipe to delete data + env files)
update.sh            # check for + apply a new release (--all for every node)
common.sh            # shared helpers (latest-release lookup, env file readers)
create_dids.sh       # create a DID per node          -> did_results.json
register_dids.sh     # register those DIDs on the network
check_balances.sh    # balance table for every DID
add_quorum.sh        # add quorum DIDs from quorum_did.json
list_configed_quorum.sh     # show each node's configured quorums
get_facuet_by_one_rbt.sh    # request faucet RBT for every DID
docker-compose.yml   # node + postgres definition (variables come from .env.nodeN)
docker-compose.branch.yml   # overlay used when BUILD_BRANCH is set
Dockerfile           # node image: downloads the release binary + kubo (IPFS)
Dockerfile.branch    # builds rubixgoplatform from a git ref instead
                     # (BUILD_CACHEBUST arg is what --rebuild changes)
entrypoint.sh        # node startup (config, swarm key, init, run)
config.template.toml # node config (DB + bootstrap peers; filled at start)
swarm/               # IPFS swarm keys (testnet / localnet / mainnet)
.env.example         # reference for all settings
.env.nodeN           # per-node config, created by node.sh (git-ignored)
data/                # created at runtime — node + Postgres data (persists)
```

> This package targets the `rubixgoplatform` **release-v1** line (Postgres + the
> `/rubix/v1` REST API). The upstream `main`/`development` branches use a different
> (legacy) API and are not compatible with this setup.
