#!/usr/bin/env bash

OUTPUT="did_results.json"

DID_PASSWORD="${DID_PASSWORD:-mypassword}"

echo '[]' > "$OUTPUT"

for port in {8000..8009}; do
  echo "Creating DID on port $port..."

  response=$(curl -s -X POST "localhost:${port}/rubix/v1/dids/create" \
    -H 'Content-Type: application/json' \
    -d "$(jq -n --arg password "$DID_PASSWORD" '{password: $password, childPath: 0}')")

  did=$(echo "$response" | jq -r '.result.did')
  peer_id=$(echo "$response" | jq -r '.result.peer_id')

  jq \
    --argjson port "$port" \
    --arg did "$did" \
    --arg peer_id "$peer_id" \
    '. += [{"port": $port, "did": $did, "peer_id": $peer_id}]' \
    "$OUTPUT" > "${OUTPUT}.tmp" && mv "${OUTPUT}.tmp" "$OUTPUT"
done

cat "$OUTPUT"
