#!/usr/bin/env bash
# Run SEVERAL Rubix nodes from this one repo. Each node is identified by an index
# (1, 2, 3, ...) and gets its own env file (.env.nodeN), compose project (-p nodeN),
# data dir (./data/nodeN), container names, and non-colliding ports.
#
#   ./node.sh up 1                 # first node  (API 20000, swarm 4001, pg 5433)
#   ./node.sh up 2                 # second node (API 20001, swarm 4002, pg 5434)
#   ./node.sh up 3                 # third node  (API 20002, swarm 4003, pg 5435)
#   ./node.sh status 1            # health board (postgres, api, ipfs, storage, cpu/mem)
#   ./node.sh logs 2              # follow a node's logs
#   ./node.sh down 3              # stop one node (its data is kept)
#   ./node.sh ls                  # list running node stacks
#
# Override any default for a node with the same flags as run.sh, e.g.:
#   ./node.sh up 2 --api-port 25000 --swarm-port 4500 --network mainnet
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

cmd="${1:-}"
case "$cmd" in
  ls) docker compose ls; exit 0;;
  up|down|logs|status) ;;
  *) echo "usage: ./node.sh <up|down|logs|status|ls> [index] [flags]   (index defaults to 1)"; exit 0;;
esac
shift   # drop the command

# index is OPTIONAL and defaults to 1 (the first/primary node)
if [[ "${1:-}" =~ ^[0-9]+$ ]]; then idx="$1"; shift; else idx=1; fi

name="node${idx}"
ENVF=".env.${name}"
compose() { docker compose --env-file "$ENVF" -p "$name" "$@"; }

if [ "$cmd" = status ]; then
  [ -f "$ENVF" ] || { echo "node $idx isn't set up yet (run ./node.sh up $idx)."; exit 1; }
  getv(){ grep -E "^$1=" "$ENVF" | cut -d= -f2- | tr -d '[:space:]'; }
  API_PORT="$(getv API_PORT)"; API_PORT="${API_PORT:-20000}"
  NODE_C="${name}-node"; PG_C="${name}-postgres"
  ok(){ printf "  \033[32m✓\033[0m %s\n" "$1"; }
  bad(){ printf "  \033[31m✗\033[0m %s\n" "$1"; }
  echo "=== Rubix node '$name'  (API :$API_PORT) ==="
  echo; echo "containers"
  for c in "$NODE_C" "$PG_C"; do
    st="$(docker inspect -f '{{.State.Status}}{{if .State.Health}} / {{.State.Health.Status}}{{end}}' "$c" 2>/dev/null || echo 'not found')"
    printf "  %-22s %s\n" "$c" "$st"
  done
  echo; echo "postgres"
  if docker exec "$PG_C" pg_isready -U rubix >/dev/null 2>&1; then
    size="$(docker exec "$PG_C" psql -U rubix -d rubix -tAc "select pg_size_pretty(pg_database_size('rubix'))" 2>/dev/null | tr -d '[:space:]' || echo '?')"
    ok "ready  (db size: ${size:-?})"
  else bad "not ready"; fi
  echo; echo "rubix api"
  if curl -s --max-time 4 "http://127.0.0.1:${API_PORT}/api/ping" >/dev/null 2>&1; then
    ok "reachable"
    pid="$(curl -s --max-time 4 "http://127.0.0.1:${API_PORT}/api/get-peer-id" 2>/dev/null | grep -o '12D3KooW[A-Za-z0-9]\{40,\}' | head -1)"
    [ -n "${pid:-}" ] && echo "    peer id : $pid"
    dids="$(curl -s --max-time 4 "http://127.0.0.1:${API_PORT}/rubix/v1/dids" 2>/dev/null | grep -o 'bafybmi[a-z0-9]*' | tr '\n' ' ')"
    echo "    dids    : ${dids:-none yet}"
  else bad "not reachable (still starting? ./node.sh logs $idx)"; fi
  echo; echo "ipfs (libp2p)"
  if docker exec "$NODE_C" sh -c 'IPFS_PATH=/app/data/.ipfs /app/ipfs id >/dev/null 2>&1'; then
    ipid="$(docker exec "$NODE_C" sh -c 'IPFS_PATH=/app/data/.ipfs /app/ipfs id -f="<id>"' 2>/dev/null || true)"
    peers="$(docker exec "$NODE_C" sh -c 'IPFS_PATH=/app/data/.ipfs /app/ipfs swarm peers 2>/dev/null | wc -l' 2>/dev/null | tr -d '[:space:]' || echo '?')"
    ok "daemon up  (peer id: ${ipid})"
    echo "    connected peers: ${peers}"
  else bad "not ready (node may still be initialising IPFS)"; fi
  echo; echo "storage"
  DATA_PATH="$(getv DATA_PATH)"; DATA_PATH="${DATA_PATH:-./data/$name}"
  du -sh "$DATA_PATH" 2>/dev/null | awk '{print "  "$1"\t"$2}' || echo "  (no data dir yet: $DATA_PATH)"
  echo; echo "resources"
  docker stats --no-stream --format '  {{.Name}}: cpu {{.CPUPerc}}, mem {{.MemUsage}}' "$NODE_C" "$PG_C" 2>/dev/null || true
  exit 0
fi

if [ "$cmd" = down ]; then
  compose down
  if [ "${1:-}" = "--wipe" ]; then
    rm -rf "./data/${name}"
    echo "node '$name' stopped and WIPED (./data/${name} removed)."
  else
    echo "node '$name' stopped (data kept under ./data/${name})."
  fi
  exit 0
fi
[ "$cmd" = logs ] && { compose logs -f rubix; exit 0; }

# ── up ──────────────────────────────────────────────────────────────────────
# seed a per-node env file the first time, with index-offset ports
if [ ! -f "$ENVF" ]; then
  cat > "$ENVF" <<EOF
RUBIX_VERSION=v1.0.0
NETWORK_MODE=testnet
POSTGRES_VERSION=18
NODE_NAME=${name}
DATA_PATH=./data/${name}
API_PORT=$((20000 + idx - 1))
API_BIND=127.0.0.1
SWARM_PORT=$((4001 + idx - 1))
PG_PORT=$((5433 + idx - 1))
EXTERNAL_IP=
EOF
  echo "Created $ENVF (API $((20000+idx-1)), swarm $((4001+idx-1)), pg $((5433+idx-1)))."
fi

set_env() { local k="$1" v="$2"; if grep -qE "^${k}=" "$ENVF"; then sed -i.bak "s|^${k}=.*|${k}=${v}|" "$ENVF" && rm -f "${ENVF}.bak"; else echo "${k}=${v}" >> "$ENVF"; fi; }
while [ $# -gt 0 ]; do
  case "$1" in
    --version|--rubix-version) set_env RUBIX_VERSION "$2"; shift 2;;
    --network)     set_env NETWORK_MODE "$2"; shift 2;;
    --api-port)    set_env API_PORT     "$2"; shift 2;;
    --api-bind)    set_env API_BIND     "$2"; shift 2;;
    --swarm-port)  set_env SWARM_PORT   "$2"; shift 2;;
    --pg-port)     set_env PG_PORT      "$2"; shift 2;;
    --external-ip) set_env EXTERNAL_IP  "$2"; shift 2;;
    --data-path)   set_env DATA_PATH    "$2"; shift 2;;
    *) echo "unknown flag: $1"; exit 1;;
  esac
done

EXTERNAL_IP="$(grep -E '^EXTERNAL_IP=' "$ENVF" | cut -d= -f2- | tr -d '[:space:]' || true)"
[ -z "$EXTERNAL_IP" ] && EXTERNAL_IP="$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}' || true)"
export EXTERNAL_IP

DATA_PATH="$(grep -E '^DATA_PATH=' "$ENVF" | cut -d= -f2- | tr -d '[:space:]')"; mkdir -p "${DATA_PATH:-./data/$name}" 2>/dev/null || true

compose up -d --build
api="$(grep -E '^API_PORT=' "$ENVF" | cut -d= -f2-)"; sw="$(grep -E '^SWARM_PORT=' "$ENVF" | cut -d= -f2-)"
echo
echo "node '$name' up  —  API http://127.0.0.1:${api}   swarm ${sw}/tcp (OPEN inbound)"
echo "  logs: ./node.sh logs ${idx}    stop: ./node.sh down ${idx}"
