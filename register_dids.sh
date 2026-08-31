#!/usr/bin/env bash

INPUT="did_results.json"

DID_PASSWORD="${DID_PASSWORD:-mypassword}"

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

    register_response=$(curl -s -X POST \
        "localhost:${port}/rubix/v1/dids/${did}/register")

    signature_id=$(echo "$register_response" | jq -r '.result.id // empty')

    if [[ -z "$signature_id" ]]; then
        echo "$current out of $total FAILED - port $port - could not get signature ID"
        continue
    fi

    signature_response=$(curl -s -X POST \
        "localhost:${port}/rubix/v1/signature" \
        -H 'Content-Type: application/json' \
        -d "$(jq -n \
            --arg id "$signature_id" \
            --arg password "$DID_PASSWORD" \
            '{id:$id,password:$password}')")

    status=$(echo "$signature_response" | jq -r '.status // false')
    message=$(echo "$signature_response" | jq -r '.message // "Unknown response"')

    if [[ "$status" == "true" ]]; then
        echo "$current out of $total done - port $port - $message"
    else
        echo "$current out of $total FAILED - port $port - $message"
    fi

done
