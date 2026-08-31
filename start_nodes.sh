#!/usr/bin/env bash

RUBIX_VERSION="${RUBIX_VERSION:-v1.0.5}"

for i in $(seq 1 10); do
  api_port=$((7999 + i))
  pg_port=$((8999 + i))

  echo "Starting node $i on API port $api_port and PG port $pg_port (version $RUBIX_VERSION)"

  ./node.sh up "$i" \
    --version "$RUBIX_VERSION" \
    --api-port "$api_port" \
    --pg-port "$pg_port"
done
