#!/usr/bin/env bash

INPUT="did_results.json"
TMP_FILE=$(mktemp)

trap 'rm -f "$TMP_FILE"' EXIT

if ! command -v jq >/dev/null 2>&1; then
    echo "Error: jq is required."
    exit 1
fi

if [[ ! -f "$INPUT" ]]; then
    echo "Error: $INPUT not found."
    exit 1
fi

echo "Fetching balances..."

jq -c '.[]' "$INPUT" | while read -r entry; do

    port=$(echo "$entry" | jq -r '.port')
    did=$(echo "$entry" | jq -r '.did')

    response=$(curl -sS \
        "http://localhost:${port}/rubix/v1/dids/${did}/balances")

    status=$(echo "$response" | jq -r '.status // false')

    if [[ "$status" == "true" ]]; then
        jq -n \
            --arg port "$port" \
            --arg did "$did" \
            --argjson result "$(echo "$response" | jq '.result')" \
            '{
                port: $port,
                did: $did,
                result: $result
            }' >> "$TMP_FILE"
    else
        message=$(echo "$response" | jq -r '.message // "API request failed"')

        jq -n \
            --arg port "$port" \
            --arg did "$did" \
            --arg error "$message" \
            '{
                port: $port,
                did: $did,
                result: {
                    error: $error
                }
            }' >> "$TMP_FILE"
    fi

done

jq -rs -r '

def flatten_value($prefix):
    if type == "object" then
        if length == 0 then
            [{
                key: $prefix,
                value: "{}"
            }]
        else
            [
                to_entries[] |
                . as $item |
                $item.value |
                flatten_value(
                    if $prefix == ""
                    then $item.key
                    else ($prefix + "." + $item.key)
                    end
                )[]
            ]
        end
    elif type == "array" then
        [{
            key: $prefix,
            value: tojson
        }]
    elif . == null then
        [{
            key: $prefix,
            value: "null"
        }]
    else
        [{
            key: $prefix,
            value: tostring
        }]
    end;

map(
    . + {
        flat: (
            (.result | del(.did)) |
            flatten_value("") |
            from_entries
        )
    }
) as $rows |

(
    [
        $rows[].flat |
        keys[]
    ]
    | unique
) as $columns |

(
    ["PORT", "DID"] +
    $columns
    | @tsv
),

(
    $rows[] |
    . as $row |
    (
        [
            $row.port,
            $row.did
        ]
        +
        [
            $columns[] as $column |
            ($row.flat[$column] // "-")
        ]
    )
    | @tsv
)

' "$TMP_FILE" |
if command -v column >/dev/null 2>&1; then
    column -t -s $'\t'
else
    cat
fi
