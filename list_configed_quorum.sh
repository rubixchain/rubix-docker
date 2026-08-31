#!/usr/bin/env bash

INPUT="did_results.json"

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

    response=$(curl -s \
        "http://localhost:${port}/rubix/v1/quorums")

    status=$(echo "$response" | jq -r '.status // false')
    message=$(echo "$response" | jq -r '.message // "Unknown response"')

    echo "=================================================="
    echo "$current out of $total"
    echo "Port     : $port"
    echo "Node DID : $did"

    if [[ "$status" == "true" ]]; then

        quorum_count=$(echo "$response" | jq '.result | length')

        echo "Quorums  : $quorum_count"

        if [[ "$quorum_count" -eq 0 ]]; then
            echo "  No quorum configured"
        else
            echo "$response" | jq -r '.result[]' | while read -r quorum; do
                echo "  - $quorum"
            done
        fi

    else
        echo "FAILED    : $message"
        echo "Response  : $response"
    fi

done

echo "=================================================="
