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
# Branch builds (run a git ref instead of a release binary):
#
#   ./update.sh --all --branch development   # switch every node to that branch
#   ./update.sh 3 --branch my-fix            # switch just node 3
#   ./update.sh --all --rebuild              # re-clone: pick up new commits on the
#                                            # branch each node already runs
#   ./update.sh --all --release              # leave the branch, go back to the
#                                            # latest release binary
#
# GitHub is queried once, no matter how many nodes are checked. In the default
# (release) mode, nodes built from a source branch are reported and skipped — they
# have no release version to bump; use --rebuild or --release on those.
#
# Every mode preserves node data: only the binary is replaced.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
. ./common.sh

ASSUME_YES=0
CHECK_ONLY=0
ALL=0
BRANCH=""
REBUILD=0
TO_RELEASE=0
targets=""

expect_branch=0
for arg in "$@"; do
  if [ "$expect_branch" -eq 1 ]; then BRANCH="$arg"; expect_branch=0; continue; fi
  case "$arg" in
    --all)          ALL=1 ;;
    --yes|-y)       ASSUME_YES=1 ;;
    --check|-n)     CHECK_ONLY=1 ;;
    --branch)       expect_branch=1 ;;
    --rebuild)      REBUILD=1 ;;
    --release)      TO_RELEASE=1 ;;
    -h|--help)      print_usage_header "$0"; exit 0 ;;
    [0-9]*)         targets="${targets}${targets:+ }${arg}" ;;
    *) echo "unknown argument: $arg"; echo; print_usage_header "$0"; exit 1 ;;
  esac
done
[ "$expect_branch" -eq 0 ] || { echo "--branch needs a git ref, e.g. --branch development"; exit 1; }

modes=$(( (${#BRANCH} > 0 ? 1 : 0) + REBUILD + TO_RELEASE ))
if [ "$modes" -gt 1 ]; then
  echo "--branch, --rebuild and --release are mutually exclusive."; exit 1
fi

if [ "$ALL" -eq 1 ]; then
  targets="$(node_indices)"
  [ -n "$targets" ] || { echo "no nodes found here (no .env.nodeN files)."; exit 1; }
elif [ -z "$targets" ]; then
  targets=1
fi

# ── branch modes: --branch <ref> / --rebuild / --release ────────────────────
if [ -n "$BRANCH" ] || [ "$REBUILD" -eq 1 ] || [ "$TO_RELEASE" -eq 1 ]; then
  release_tag=""
  if [ "$TO_RELEASE" -eq 1 ]; then
    echo "Checking ${RUBIX_REPO} for the latest release ..."
    release_tag="$(latest_release_or_fallback)"
    echo "latest release: $release_tag"
    echo
  fi

  todo=""
  for idx in $targets; do
    envf=".env.node${idx}"
    if [ ! -f "$envf" ]; then
      printf "  node %-3s %s\n" "$idx" "not set up (run ./node.sh up $idx first) — skipped"
      continue
    fi
    cur_branch="$(getenvv "$envf" BUILD_BRANCH)"
    cur_ver="$(getenvv "$envf" RUBIX_VERSION)"
    now="${cur_branch:+branch $cur_branch}"; now="${now:-$cur_ver}"

    if [ -n "$BRANCH" ]; then
      printf "  node %-3s %s\n" "$idx" "$now -> branch $BRANCH"
    elif [ "$REBUILD" -eq 1 ]; then
      if [ -z "$cur_branch" ]; then
        printf "  node %-3s %s\n" "$idx" "$now — release build, nothing to re-clone — skipped"
        continue
      fi
      printf "  node %-3s %s\n" "$idx" "branch $cur_branch — re-clone for new commits"
    else
      if [ -z "$cur_branch" ]; then
        printf "  node %-3s %s\n" "$idx" "$now — already a release build — skipped"
        continue
      fi
      printf "  node %-3s %s\n" "$idx" "branch $cur_branch -> release $release_tag"
    fi
    todo="${todo}${todo:+ }${idx}"
  done

  echo
  [ -n "$todo" ] || { echo "Nothing to do."; exit 0; }
  n="$(echo "$todo" | wc -w | tr -d '[:space:]')"

  if [ "$CHECK_ONLY" -eq 1 ]; then
    echo "--check: nothing was changed ($n node(s) would be rebuilt: $todo)"
    exit 0
  fi

  if [ -n "$BRANCH" ]; then
    echo "Will rebuild $n node(s) from branch '$BRANCH': $todo"
  elif [ "$REBUILD" -eq 1 ]; then
    echo "Will re-clone and rebuild $n node(s) from their current branch: $todo"
  else
    echo "Will move $n node(s) back to release $release_tag: $todo"
  fi
  if [ "$TO_RELEASE" -eq 1 ]; then
    echo "(Downloads the release binary and rebuilds each container.)"
  else
    echo "(Compiles from source — the first node is slow, the rest reuse its layers.)"
  fi
  echo "DIDs, token chains and Postgres data are kept."
  if [ "$ASSUME_YES" -ne 1 ]; then
    if [ -t 0 ]; then
      read -r -p "Proceed? [y/N] " ans || ans=""
    else
      echo "Not an interactive shell — re-run with --yes."
      exit 1
    fi
    case "$ans" in y|Y|yes|YES) ;; *) echo "Skipped."; exit 0;; esac
  fi

  # One cache-bust value for the whole run: node 1 does the clone + compile, the
  # others reuse those layers instead of recompiling ten times.
  if [ "$TO_RELEASE" -ne 1 ]; then
    BUILD_CACHEBUST="$(date +%s)"; export BUILD_CACHEBUST
  fi

  ok=""; bad=""
  for idx in $todo; do
    echo
    echo "── node $idx ───────────────────────────────────────────"
    if [ -n "$BRANCH" ]; then
      cmd=(./node.sh up "$idx" --branch "$BRANCH" --rebuild)
    elif [ "$REBUILD" -eq 1 ]; then
      cmd=(./node.sh up "$idx" --rebuild)
    else
      cmd=(./node.sh up "$idx" --version "$release_tag")
    fi
    if "${cmd[@]}"; then ok="${ok}${ok:+ }${idx}"; else
      echo "node $idx FAILED — continuing with the rest."
      bad="${bad}${bad:+ }${idx}"
    fi
  done

  echo
  [ -n "$ok" ] && echo "Rebuilt: $ok"
  if [ -n "$bad" ]; then echo "Failed: $bad  (check ./node.sh logs <n>)"; exit 1; fi
  echo "Done."
  exit 0
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
