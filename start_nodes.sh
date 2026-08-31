#!/usr/bin/env bash

for i in $(seq 1 10); do
  api_port=$((7999 + i))
  pg_port=$((8999 + i))

  echo "Starting node $i on API port $api_port and PG port $pg_port"

  ./node.sh up "$i" \
    --api-port "$api_port" \
    --pg-port "$pg_port"
done
