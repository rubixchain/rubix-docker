#!/usr/bin/env bash
# Check for a newer rubixgoplatform release and, if you confirm, update + rebuild.
# Never updates automatically — it always asks first. Your data is preserved.
#
#   ./update.sh          # check, prompt, update if you say yes
#   ./update.sh --yes    # check and update without prompting (for automation)
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
[ -f .env ] || cp .env.example .env

REPO="rubixchain/rubixgoplatform"
ASSUME_YES=0; [ "${1:-}" = "--yes" ] && ASSUME_YES=1

current="$(grep -E '^RUBIX_VERSION=' .env | cut -d= -f2- | tr -d '[:space:]')"
[ -n "$current" ] || current="v1.0.0"

echo "Installed node version : $current"
echo "Checking for updates ..."
latest="$(curl -s --max-time 10 "https://api.github.com/repos/$REPO/releases/latest" \
          | grep -o '"tag_name": *"[^"]*"' | head -1 | cut -d'"' -f4)"

if [ -z "$latest" ]; then
  echo "Could not reach GitHub to check the latest release (rate-limited or offline). Try again later."
  exit 1
fi
echo "Latest release         : $latest"

if [ "$current" = "$latest" ]; then
  echo "You're already up to date."
  exit 0
fi

# is 'latest' actually newer than what we run? (avoid suggesting a downgrade)
newest="$(printf '%s\n%s\n' "$current" "$latest" | sort -V | tail -1)"
if [ "$newest" != "$latest" ]; then
  echo "Your pinned version ($current) is ahead of the latest published release ($latest) — nothing to do."
  exit 0
fi

echo
echo "An update is available:  $current  ->  $latest"
echo "(This rebuilds the node container. Your DID, token chains and Postgres data are kept.)"

if [ "$ASSUME_YES" -ne 1 ]; then
  read -r -p "Update now? [y/N] " ans
  case "$ans" in y|Y|yes|YES) ;; *) echo "Skipped. Run ./update.sh again whenever you're ready."; exit 0;; esac
fi

# pin the new version and rebuild (run.sh handles EXTERNAL_IP + build)
sed -i.bak "s/^RUBIX_VERSION=.*/RUBIX_VERSION=$latest/" .env && rm -f .env.bak
echo "Set RUBIX_VERSION=$latest in .env. Rebuilding ..."
./run.sh
echo
echo "Done — node updated to $latest. Verify:  docker compose logs -f rubix"
