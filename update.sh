#!/usr/bin/env bash
# Check for a newer rubixgoplatform release and, if you confirm, update + rebuild.
# Never updates automatically — it always asks first. Your data is preserved.
#
#   ./update.sh              # check node 1, prompt, update if you say yes
#   ./update.sh 2            # check node 2
#   ./update.sh 2 5 7        # check several nodes
#   ./update.sh --all        # check EVERY node in this folder, update them in one go
#   ./update.sh --all --yes  # same, no prompt (for automation/cron)
#   ./update.sh --check      # just report versions, change nothing
#
# GitHub is queried once, no matter how many nodes are checked. Nodes built from a
# source branch (BUILD_BRANCH set) are reported and skipped — they have no release
# version to bump.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
. ./common.sh

ASSUME_YES=0
CHECK_ONLY=0
ALL=0
targets=""

for arg in "$@"; do
  case "$arg" in
    --all)          ALL=1 ;;
    --yes|-y)       ASSUME_YES=1 ;;
    --check|-n)     CHECK_ONLY=1 ;;
    -h|--help)      print_usage_header "$0"; exit 0 ;;
    [0-9]*)         targets="${targets}${targets:+ }${arg}" ;;
    *) echo "unknown argument: $arg"; echo; print_usage_header "$0"; exit 1 ;;
  esac
done

if [ "$ALL" -eq 1 ]; then
  targets="$(node_indices)"
  [ -n "$targets" ] || { echo "no nodes found here (no .env.nodeN files)."; exit 1; }
elif [ -z "$targets" ]; then
  targets=1
fi

echo "Checking ${RUBIX_REPO} for the latest release ..."
latest="$(latest_release)"
if [ -z "$latest" ]; then
  echo "Could not reach GitHub to check the latest release (rate-limited or offline). Try again later."
  exit 1
fi
echo "latest release: $latest"
echo

# ── survey every target before changing anything ────────────────────────────
to_update=""
for idx in $targets; do
  envf=".env.node${idx}"
  if [ ! -f "$envf" ]; then
    printf "  node %-3s %s\n" "$idx" "not set up (run ./node.sh up $idx first) — skipped"
    continue
  fi
  branch="$(getenvv "$envf" BUILD_BRANCH)"
  if [ -n "$branch" ]; then
    printf "  node %-3s %s\n" "$idx" "built from branch '$branch' — skipped (no release to bump)"
    continue
  fi
  current="$(getenvv "$envf" RUBIX_VERSION)"
  [ -n "$current" ] || current="v1.0.0"

  if [ "$current" = "$latest" ]; then
    printf "  node %-3s %s\n" "$idx" "$current — up to date"
    continue
  fi
  newest="$(printf '%s\n%s\n' "$current" "$latest" | sort -V | tail -1)"
  if [ "$newest" != "$latest" ]; then
    printf "  node %-3s %s\n" "$idx" "$current — ahead of the latest release ($latest), left alone"
    continue
  fi
  printf "  node %-3s %s\n" "$idx" "$current -> $latest  ** update available **"
  to_update="${to_update}${to_update:+ }${idx}"
done

echo
if [ -z "$to_update" ]; then
  echo "Nothing to update."
  exit 0
fi

count="$(echo "$to_update" | wc -w | tr -d '[:space:]')"
if [ "$CHECK_ONLY" -eq 1 ]; then
  echo "$count node(s) can be updated to $latest: $to_update"
  echo "(--check: nothing was changed)"
  exit 0
fi

echo "Will update $count node(s) to $latest: $to_update"
echo "(Rebuilds each node container, one at a time. DIDs, token chains and Postgres data are kept.)"
if [ "$ASSUME_YES" -ne 1 ]; then
  if [ -t 0 ]; then
    read -r -p "Proceed? [y/N] " ans || ans=""
  else
    echo "Not an interactive shell — re-run with --yes to update without prompting."
    exit 1
  fi
  case "$ans" in y|Y|yes|YES) ;; *) echo "Skipped. Run ./update.sh again whenever you're ready."; exit 0;; esac
fi

updated=""; failed=""
for idx in $to_update; do
  envf=".env.node${idx}"
  echo
  echo "── node $idx → $latest ─────────────────────────────────"
  sed -i.bak "s/^RUBIX_VERSION=.*/RUBIX_VERSION=$latest/" "$envf" && rm -f "${envf}.bak"
  if ./node.sh up "$idx"; then
    updated="${updated}${updated:+ }${idx}"
  else
    echo "node $idx FAILED to rebuild — continuing with the rest."
    failed="${failed}${failed:+ }${idx}"
  fi
done

echo
[ -n "$updated" ] && echo "Updated to $latest: $updated"
if [ -n "$failed" ]; then
  echo "Failed: $failed  (check ./node.sh logs <n>)"
  exit 1
fi
echo "Done."
