#!/usr/bin/env bash
# Shortcut for the node health board — identical to:  ./node.sh status
#   ./status.sh        # node 1
#   ./status.sh 2      # node 2
exec "$(dirname "${BASH_SOURCE[0]}")/node.sh" status "$@"
