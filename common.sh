#!/usr/bin/env bash
# Shared helpers for the node scripts. Source it AFTER cd'ing to the repo root:
#   . ./common.sh

RUBIX_REPO="${RUBIX_REPO:-rubixchain/rubixgoplatform}"
# Used only when GitHub can't be reached (offline, rate-limited, API change).
FALLBACK_VERSION="${FALLBACK_VERSION:-v1.0.5}"

# Newest published release tag (e.g. v1.0.6), or "" if GitHub can't be reached.
latest_release() {
  curl -fsSL --max-time 10 "https://api.github.com/repos/${RUBIX_REPO}/releases/latest" 2>/dev/null \
    | grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4 || true
}

# Same, but falls back to FALLBACK_VERSION (with a warning) instead of returning "".
latest_release_or_fallback() {
  local v
  v="$(latest_release)"
  if [ -z "$v" ]; then
    echo "WARNING: couldn't reach GitHub for the latest ${RUBIX_REPO} release" >&2
    echo "         (offline or rate-limited) — using ${FALLBACK_VERSION} instead." >&2
    v="$FALLBACK_VERSION"
  fi
  printf '%s' "$v"
}

# Indices of nodes that already exist (have a .env.nodeN), numerically sorted.
node_indices() {
  ls .env.node* 2>/dev/null \
    | sed -n 's/^\.env\.node\([0-9][0-9]*\)$/\1/p' | sort -n | tr '\n' ' ' || true
}

# getenvv <envfile> <KEY> — value of KEY, or "" if absent.
getenvv() { grep -E "^$2=" "$1" 2>/dev/null | cut -d= -f2- | tr -d '[:space:]' || true; }

# Print the leading comment block of a script as its --help text.
print_usage_header() {
  awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$1"
}
