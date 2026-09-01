#!/usr/bin/env bash
# Start the local fleet of Rubix nodes (default: 10).
#
# The network is chosen ONCE, when a node is first created, and is then stored in
# .env.nodeN. Every later run reuses whatever that file says — so:
#
#   ./start_nodes.sh               # first time: create all nodes on TESTNET (the default)
#   ./start_nodes.sh --mainnet     # first time: create all nodes on mainnet
#   ./start_nodes.sh               # afterwards: each node starts on its stored network
#
# Mainnet is never entered by accident: it takes an explicit --mainnet on first init.
#
# Flags:
#   --mainnet | --testnet | --localnet | --network <net>
#   --version <v>     rubixgoplatform release to run. Defaults to the LATEST GitHub
#                     release when a node is first created; "latest" forces a re-check
#                     for nodes that already exist.
#   --nodes <n>       how many nodes to start (default 10)
#   --wipe-switch     DESTRUCTIVE: allow moving already-created nodes to a different
#                     network by deleting their data dir first (DIDs/keys/tokens go too)
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
. ./common.sh

DEFAULT_NETWORK=testnet          # first-init default; mainnet requires an explicit flag
NODE_COUNT="${NODE_COUNT:-10}"
NETWORK="${NETWORK_MODE:-}"      # explicit override; empty = "use what's stored"
VERSION="${RUBIX_VERSION:-}"     # explicit override; empty = "use what's stored"
WIPE_SWITCH=0

usage() { print_usage_header "$0"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --mainnet)      NETWORK=mainnet;  shift;;
    --testnet)      NETWORK=testnet;  shift;;
    --localnet)     NETWORK=localnet; shift;;
    --network)      NETWORK="${2:-}"; shift 2;;
    --version)      VERSION="${2:-}"; shift 2;;
    --nodes)        NODE_COUNT="${2:-}"; shift 2;;
    --wipe-switch)  WIPE_SWITCH=1;    shift;;
    -h|--help)      usage; exit 0;;
    *) echo "unknown flag: $1"; echo; usage; exit 1;;
  esac
done

case "${NETWORK:-$DEFAULT_NETWORK}" in
  mainnet|testnet|localnet) ;;
  *) echo "invalid network '$NETWORK' (use mainnet | testnet | localnet)"; exit 1;;
esac

getv() { grep -E "^$2=" "$1" 2>/dev/null | cut -d= -f2- | tr -d '[:space:]' || true; }

# Which nodes already exist? (an existing .env.nodeN means the network is already fixed)
new_nodes=""
for i in $(seq 1 "$NODE_COUNT"); do
  [ -f ".env.node${i}" ] || new_nodes="${new_nodes}${new_nodes:+ }${i}"
done

# First-time init with no flag → testnet. Only --mainnet puts new nodes on mainnet.
if [ -n "$new_nodes" ] && [ -z "$NETWORK" ]; then
  NETWORK="$DEFAULT_NETWORK"
  echo "Creating node(s) ${new_nodes} on ${NETWORK} (default). Use --mainnet for mainnet."
fi

# Version to use for nodes being created now: --version <v>, or the latest release.
# The GitHub call happens only when it's actually needed.
if [ "$VERSION" = "latest" ]; then
  VERSION="$(latest_release_or_fallback)"
  echo "Latest ${RUBIX_REPO} release: $VERSION"
fi
DEFAULT_VERSION=""
if [ -n "$new_nodes" ] && [ -z "$VERSION" ]; then
  DEFAULT_VERSION="$(latest_release_or_fallback)"
  echo "New nodes will run the latest ${RUBIX_REPO} release: $DEFAULT_VERSION"
fi

for i in $(seq 1 "$NODE_COUNT"); do
  envf=".env.node${i}"
  api_port=$((7999 + i))
  pg_port=$((8999 + i))
  args=(--api-port "$api_port" --pg-port "$pg_port")

  # Snapshot the stored config BEFORE any wipe (a wipe deletes $envf).
  existed=0; stored_net=""; stored_ver=""; stored_branch=""
  if [ -f "$envf" ]; then
    existed=1
    stored_net="$(getv "$envf" NETWORK_MODE)"
    stored_ver="$(getv "$envf" RUBIX_VERSION)"
    stored_branch="$(getv "$envf" BUILD_BRANCH)"
  fi

  if [ "$existed" -eq 1 ] && [ -n "$NETWORK" ] && [ "$NETWORK" != "$stored_net" ]; then
    if [ "$WIPE_SWITCH" -eq 1 ]; then
      echo "node $i: switching $stored_net -> $NETWORK (wiping ./data/node${i})"
      ./node.sh down "$i" --wipe
      existed=0          # env file is gone; it gets re-seeded by ./node.sh up
    else
      echo "ERROR: node $i is already initialised on '$stored_net' but you asked for '$NETWORK'."
      echo "       Rubix refuses to reuse a data dir across networks. To move it, re-run with"
      echo "       --wipe-switch (this DELETES ./data/node${i}: DIDs, keys and tokens included)."
      exit 1
    fi
  fi

  net="${NETWORK:-$stored_net}"
  args+=(--network "$net")

  # Version/branch. For an existing node, leave RUBIX_VERSION and BUILD_BRANCH alone
  # unless --version was given — passing --version clears BUILD_BRANCH in node.sh.
  if [ -n "$VERSION" ]; then
    ver="$VERSION"; args+=(--version "$ver")
  elif [ "$existed" -eq 1 ]; then
    ver="${stored_branch:+branch $stored_branch}"; ver="${ver:-$stored_ver}"
  elif [ -n "$stored_branch" ]; then          # node we just wiped — keep its branch
    ver="branch $stored_branch"; args+=(--branch "$stored_branch")
  elif [ -n "$stored_ver" ]; then             # node we just wiped — keep its version
    ver="$stored_ver"; args+=(--version "$ver")
  else                                        # brand-new node — latest release
    [ -n "$DEFAULT_VERSION" ] || DEFAULT_VERSION="$(latest_release_or_fallback)"
    ver="$DEFAULT_VERSION"; args+=(--version "$ver")
  fi

  echo "Starting node $i on API port $api_port and PG port $pg_port (version $ver, network $net)"
  ./node.sh up "$i" "${args[@]}"
done
