#!/usr/bin/env bash
# Shortcut for stopping your primary node — identical to:  ./node.sh down
#   ./stop.sh            stop node 1 (data kept)
#   ./stop.sh --wipe     stop node 1 and delete its data
#   ./stop.sh 2          stop node 2     (./stop.sh 2 --wipe to wipe it)
exec "$(dirname "${BASH_SOURCE[0]}")/node.sh" down "$@"
