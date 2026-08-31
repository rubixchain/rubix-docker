#!/usr/bin/env bash

INPUT="quorum_did.json"

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

    response=$(curl -s -X POST \
        "http://localhost:${port}/rubix/v1/quorums/add" \
        -H "Content-Type: application/json" \
        -d "$(jq -n \
            --arg did "$did" \
            '{did: $did}')")

    status=$(echo "$response" | jq -r '.status // false')
    message=$(echo "$response" | jq -r '.message // "Unknown response"')

    if [[ "$status" == "true" ]]; then
        echo "$current out of $total done - port $port - $message"
    else
        echo "$current out of $total FAILED - port $port - $message"
        echo "Response: $response"
    fi

done
