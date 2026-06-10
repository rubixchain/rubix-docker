#!/bin/bash
set -e

echo "Starting Rubix node..."

cd /app   # CRITICAL — Rubix uses ./ipfs (relative path), CWD must be /app

DB_NAME=${DB_NAME:-rubix}

DATA_DIR=/app/data
CONFIG_FILE=$DATA_DIR/config.toml

mkdir -p $DATA_DIR

# -------------------------
# Network validation — refuse to switch networks on an existing data dir
# -------------------------
if [ -f "$CONFIG_FILE" ]; then
  EXISTING=$(grep network_mode $CONFIG_FILE | awk -F '"' '{print $2}')
  if [ "$EXISTING" != "$NETWORK_MODE" ]; then
    echo "ERROR: Network mismatch. Existing=$EXISTING New=$NETWORK_MODE"
    echo "Wipe the data dir before switching networks."
    exit 1
  fi
fi

# -------------------------
# Generate config from template (envsubst fills DB host/port + network mode)
# -------------------------
echo "Generating config..."
envsubst < /app/config.template.toml > $CONFIG_FILE

# -------------------------
# Wait for Postgres
# -------------------------
echo "Waiting for Postgres at $DB_HOST:$DB_PORT ..."
until pg_isready -h $DB_HOST -p $DB_PORT -U rubix; do
  sleep 2
done
echo "Postgres ready"

# -------------------------
# Clear incomplete IPFS state from a prior failed start (.ipfs without config)
# -------------------------
IPFS_DIR="$DATA_DIR/.ipfs"
if [ -d "$IPFS_DIR" ] && [ ! -f "$IPFS_DIR/config" ]; then
  echo "WARNING: Incomplete IPFS state detected — removing stale .ipfs/ for a clean re-init."
  rm -rf "$IPFS_DIR"
fi

# -------------------------
# Place the swarm key for the chosen network into CWD (Rubix reads it relatively)
# -------------------------
echo "Placing swarm key for $NETWORK_MODE"
case "$NETWORK_MODE" in
  localnet) cp /swarm/localnetswarm.key ./localnetswarm.key ;;
  testnet)  cp /swarm/testnetswarm.key  ./testnetswarm.key ;;
  mainnet)  cp /swarm/swarm.key         ./swarm.key ;;
  *) echo "Invalid NETWORK_MODE: $NETWORK_MODE (use localnet | testnet | mainnet)"; exit 1 ;;
esac

# -------------------------
# Initialize once (config.toml). IPFS init happens during run.
# -------------------------
if [ ! -f "$DATA_DIR/initialized" ]; then
  echo "Initializing Rubix..."
  ./rubixgoplatform init -p $DATA_DIR
  touch $DATA_DIR/initialized
fi

# -------------------------
# Run (triggers ipfs init + daemon internally)
# -------------------------
echo "Starting Rubix..."
exec ./rubixgoplatform run -p $DATA_DIR
