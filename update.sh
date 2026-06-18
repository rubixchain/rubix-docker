#!/usr/bin/env bash
# Check for a newer rubixgoplatform release and, if you confirm, update + rebuild.
# Never updates automatically — it always asks first. Your data is preserved.
#
#   ./update.sh          # check node 1, prompt, update if you say yes
#   ./update.sh 2        # check node 2
#   ./update.sh 2 --yes  # check and update node 2 without prompting (for automation)
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

REPO="rubixchain/rubixgoplatform"
ASSUME_YES=0

# parse: optional numeric index, optional --yes
idx=1
for arg in "$@"; do
  case "$arg" in
    --yes) ASSUME_YES=1 ;;
    [0-9]*) idx="$arg" ;;
    *) echo "unknown argument: $arg"; exit 1 ;;
  esac
done

ENVF=".env.node${idx}"
[ -f "$ENVF" ] || { echo "node $idx isn't set up yet (run ./node.sh up $idx first)."; exit 1; }

# Branch-built nodes don't have a release version to update.
if grep -qE "^BUILD_BRANCH=.+" "$ENVF" 2>/dev/null; then
  branch="$(grep -E '^BUILD_BRANCH=' "$ENVF" | cut -d= -f2- | tr -d '[:space:]')"
  echo "node $idx is running from source branch '$branch', not a release binary."
  echo "To switch to a release: remove BUILD_BRANCH from $ENVF, then run ./node.sh up $idx --version <v>."
  exit 0
fi

current="$(grep -E '^RUBIX_VERSION=' "$ENVF" | cut -d= -f2- | tr -d '[:space:]' || true)"
[ -n "$current" ] || current="v1.0.0"

echo "node $idx — installed version : $current"
echo "Checking for updates ..."
latest="$(curl -s --max-time 10 "https://api.github.com/repos/$REPO/releases/latest" \
          | grep -o '"tag_name": *"[^"]*"' | head -1 | cut -d'"' -f4)"

if [ -z "$latest" ]; then
  echo "Could not reach GitHub to check the latest release (rate-limited or offline). Try again later."
  exit 1
fi
echo "node $idx — latest release    : $latest"

if [ "$current" = "$latest" ]; then
  echo "Already up to date."
  exit 0
fi

newest="$(printf '%s\n%s\n' "$current" "$latest" | sort -V | tail -1)"
if [ "$newest" != "$latest" ]; then
  echo "Pinned version ($current) is ahead of latest published release ($latest) — nothing to do."
  exit 0
fi

echo
echo "Update available:  $current  ->  $latest"
echo "(Rebuilds the node container. DID, token chains, and Postgres data are kept.)"

if [ "$ASSUME_YES" -ne 1 ]; then
  read -r -p "Update node $idx now? [y/N] " ans
  case "$ans" in y|Y|yes|YES) ;; *) echo "Skipped. Run ./update.sh $idx again whenever you're ready."; exit 0;; esac
fi

sed -i.bak "s/^RUBIX_VERSION=.*/RUBIX_VERSION=$latest/" "$ENVF" && rm -f "${ENVF}.bak"
echo "Set RUBIX_VERSION=$latest in $ENVF. Rebuilding node $idx ..."
./node.sh up "$idx"
echo
echo "Done — node $idx updated to $latest."
