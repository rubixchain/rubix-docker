# Rubix Node — Docker

Run a **Rubix node** with one command. The image downloads the official
[`rubixgoplatform`](https://github.com/rubixchain/rubixgoplatform/releases) release
binary (no Go build), pairs it with its own Postgres + IPFS, and persists everything
so a reboot resumes cleanly. Built for exchanges, businesses, and anyone who wants to
run a node with minimal friction.

One tool does everything: **`./node.sh`** (`run.sh`, `stop.sh`, `status.sh` are
shortcuts for the common commands).

---

## 1. Requirements

- A Linux host (VM or server), amd64 or arm64
- **Docker + Docker Compose v2** — check with `docker compose version`
- Outbound internet (to reach the network's bootstrap peers + IPFS)
- ~2 GB RAM and a few GB disk per node to start

## 2. First-time setup

**a. Install Docker** (skip if you already have it):

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker "$USER"     # run docker without sudo
newgrp docker                       # apply the group to this shell (or log out/in)
```

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
./node.sh down --wipe         # stop and delete this node's data
```

Set anything from the command line — each flag is saved, so the node keeps it next
time:

```bash
./node.sh up --api-port 20005 --swarm-port 4010 --data-path /mnt/rubix-data
./node.sh up --network mainnet --version v1.0.1 --external-ip 203.0.113.7
```

| Flag | Default | Meaning |
|---|---|---|
| `--version <tag>` | `v1.0.0` | rubixgoplatform release to run (bump to upgrade) |
| `--network <mode>` | `testnet` | `testnet` / `mainnet` / `localnet` |
| `--api-port <port>` | `20000` | host port for the node HTTP API (it always runs on 20000 *inside* the container — this is the port you connect to) |
| `--api-bind <ip>` | `127.0.0.1` | interface the API binds to. `0.0.0.0` only if a remote backend needs it (then firewall it — the API has no auth) |
| `--swarm-port <port>` | `4002` | host port for the P2P/IPFS swarm — **must be reachable from the internet** |
| `--pg-port <port>` | `5432` | Postgres host port (kept on localhost) |
| `--external-ip <ip>` | auto | public/LAN IP announced to the DHT (auto-detected if unset) |
| `--data-path <path>` | `./data/nodeN` | where node + DB data is stored (relative or absolute) |

You never have to create or edit an env file — `node.sh` writes one per node
(`.env.nodeN`) for you. You *can* edit it directly if you prefer.

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

## 5. Stopping, resuming, restarting & reboots

Your data (the node's **DID/keys**, token chains, IPFS repo, and Postgres) lives under
`DATA_PATH` (default `./data/nodeN`) as bind-mounts — it is **never** deleted by a
normal stop. Both containers run with `restart: unless-stopped`. So:

| Situation | What happens | What you do |
|---|---|---|
| The node process crashes | Docker **auto-restarts** it | nothing |
| The host **reboots** while the node was running | Docker **auto-starts** it on boot | nothing — verify with `./node.sh status` |
| You ran `./node.sh down` | containers are stopped/removed (data kept) | `./node.sh up` to resume — **same DID, same data** |
| You ran `./node.sh down --wipe` | containers stopped **and data deleted** | `./node.sh up` starts a brand-new node |

In short: a node **resumes with the same identity** after a crash, reboot, or
`down` → `up`. The only way to lose data is `--wipe` (or deleting the data dir).

> Requires Docker to start on boot — it does by default on standard installs
> (`sudo systemctl enable docker` if yours doesn't).

## 6. Updating the node version

Versions are **pinned** — a node never changes version on a plain restart.

```bash
./update.sh           # checks the latest release, shows current -> latest, asks before updating
./update.sh --yes     # update without the prompt (automation)
```

Or pin a specific version yourself:

```bash
./node.sh up --version v1.0.1
```

Either way your data is untouched — only the binary is replaced.

### Build from a source branch (advanced)

By default a node runs the official **release binary**. To build from a
`rubixgoplatform` git **branch, tag, or commit** instead — e.g. to test a fix before
it's released:

```bash
./node.sh up 1 --branch development     # clone + compile that ref, then run
```

The branch is remembered in `.env.nodeN`, so every later restart rebuilds from it.
`./update.sh` skips branch-built nodes (there's no release to compare against). Return
to a release binary at any time:

```bash
./node.sh up 1 --version v1.0.0         # clears the branch, back to the release
```

To build from a fork or a different main package path, override the `BUILD_REPO` /
`BUILD_PKG` / `GO_VERSION` build args in `Dockerfile.branch`.

## 7. Ports to open

| Port | Direction | Open to | Why |
|---|---|---|---|
| **`SWARM_PORT` (4002) TCP** | **inbound** | **the internet** | **Required.** The libp2p/IPFS P2P port. The node announces `EXTERNAL_IP:SWARM_PORT`; peers and quorums dial it to reach you. **Port-forward it if behind NAT.** Without it the node can call out but can't be reliably dialled (receiving tokens, acting as quorum). |
| `API_PORT` (20000) TCP | inbound | **trusted only** | HTTP API, **no authentication**. Keep on `127.0.0.1` (default) or restrict to your backend's IP. Never expose publicly. |
| `PG_PORT` (5432) TCP | — | nobody | Postgres is bound to localhost; leave closed. |
| any | **outbound** | the internet | The node needs to reach bootstrap peers + IPFS. Usually already allowed. |

`ufw` example (open only the swarm port publicly):

```bash
sudo ufw allow 4002/tcp        # SWARM_PORT — and 4002, 4003, ... for extra nodes
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

## 9. Troubleshooting

- **Can't reach the API from another machine** → it's bound to `127.0.0.1` by design.
  Start with `--api-bind 0.0.0.0`, open the port to your backend only, and never to
  the public internet (no auth).
- **Public IP / peers can't reach the node** → open/forward `SWARM_PORT` inbound
  (firewall + router). Check `./node.sh status` → "connected peers".
- **Node container exits immediately** → `./node.sh logs`. A `network_mode` mismatch
  ("Existing=… New=…") means the data dir was created on a different network — wipe it
  (`./node.sh down --wipe`) before switching networks.
- **Port already in use** → pick another with `--api-port` / `--swarm-port` /
  `--pg-port`, or run as a different node index.
- **Reset everything for this node** → `./node.sh down --wipe` then `./node.sh up`.
- **Changing the Postgres major version** (e.g. 16 → 18) is **not in-place** — a data
  dir created by the old version won't start under the new one. Just start fresh:
  `./node.sh down 1 --wipe` then `./node.sh up 1` (the node re-creates its DID and
  state on a clean Postgres 18).

## 10. Files in this folder

```
node.sh             # the one tool: up / down / logs / status / ls
run.sh stop.sh status.sh   # shortcuts for node.sh up / down / status
update.sh           # check for + apply a new release (with confirmation)
docker-compose.yml  # node + postgres definition (variables come from .env.nodeN)
Dockerfile          # node image: downloads the release binary + kubo (IPFS)
entrypoint.sh       # node startup (config, swarm key, init, run)
config.template.toml# node config (DB + bootstrap peers; filled at start)
swarm/              # IPFS swarm keys (testnet / localnet / mainnet)
.env.example        # reference for all settings
data/               # created at runtime — node + Postgres data (persists)
```

> This package targets the `rubixgoplatform` **release-v1** line (Postgres + the
> `/rubix/v1` REST API). The upstream `main`/`development` branches use a different
> (legacy) API and are not compatible with this setup.
