#!/usr/bin/env bash
# Stop the local fleet of Rubix nodes (default: 10).
#
#   ./kill_nodes.sh            # stop them; data and .env.nodeN are kept
#   ./kill_nodes.sh --wipe     # stop AND delete ./data/nodeN + .env.nodeN for every node
#                              # (DESTRUCTIVE: DIDs, keys, tokens and IPFS identity go too)
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

NODE_COUNT="${NODE_COUNT:-10}"
WIPE=""
case "${1:-}" in
  --wipe) WIPE="--wipe";;
  "") ;;
  *) echo "usage: ./kill_nodes.sh [--wipe]"; exit 1;;
esac

if [ -n "$WIPE" ]; then
  echo "About to STOP and WIPE nodes 1-${NODE_COUNT}: ./data/nodeN and .env.nodeN will be deleted."
  echo "DIDs, private keys, tokens and IPFS identities are NOT recoverable afterwards."
  if [ -t 0 ]; then
    read -r -p "Type 'wipe' to continue: " confirm || confirm=""
    [ "$confirm" = "wipe" ] || { echo "aborted."; exit 1; }
  else
    echo "(non-interactive: proceeding)"
  fi
fi

for i in $(seq 1 "$NODE_COUNT"); do
  echo "Shutting down node $i"
  ./node.sh down "$i" $WIPE
done
