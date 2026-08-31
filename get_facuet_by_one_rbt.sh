#!/usr/bin/env bash

INPUT="did_results.json"
FAUCET_URL="https://faucet.rubix.net/increment"

if ! command -v jq >/dev/null 2>&1; then
    echo "Error: jq is required."
    exit 1
fi

if [[ ! -f "$INPUT" ]]; then
    echo "Error: $INPUT not found."
    exit 1
fi

total=$(jq 'length' "$INPUT")
current=0

jq -c '.[]' "$INPUT" | while read -r entry; do

    current=$((current + 1))

    port=$(echo "$entry" | jq -r '.port')
    did=$(echo "$entry" | jq -r '.did')

    echo "[$current/$total] Port $port - DID $did"

    response=$(curl -sS \
        -X POST "$FAUCET_URL" \
        -H 'Accept: */*' \
        -H 'Content-Type: application/json' \
        -H 'Origin: https://faucet.rubix.net' \
        -H 'Referer: https://faucet.rubix.net/' \
        --data "$(jq -n --arg did "$did" '{username: $did}')")

    echo "Response: $response"
    echo

    # Small delay to avoid hammering the faucet
    sleep 1

done
