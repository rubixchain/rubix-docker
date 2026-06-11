#!/usr/bin/env bash
# Shortcut for starting your primary node — identical to:  ./node.sh up
# Any flags are passed straight through, e.g.  ./run.sh --api-port 20005
#
# Run more nodes with:  ./node.sh up 2   ./node.sh up 3   ...
exec "$(dirname "${BASH_SOURCE[0]}")/node.sh" up "$@"
