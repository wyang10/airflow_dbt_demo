#!/usr/bin/env bash
set -euo pipefail

# Usage: prune_ge.sh [KEEP]
# KEEP: how many latest run directories to keep per suite (default 5)

KEEP="${1:-5}"

ROOTS=(
  "great_expectations/uncommitted/validations"
  "great_expectations/uncommitted/data_docs/local_site/validations"
)

for ROOT in "${ROOTS[@]}"; do
  [[ -d "$ROOT" ]] || continue
  for SUITE in "$ROOT"/*; do
    [[ -d "$SUITE" ]] || continue
    echo "Pruning $SUITE (keep $KEEP latest)"
    # List run directories newest-first; remove everything after KEEP
    # Use awk to select rows beyond KEEP and remove them safely
    ls -1dt "$SUITE"/* 2>/dev/null | awk -v k="$KEEP" 'NR>k' | while read -r victim; do
      [[ -n "$victim" ]] || continue
      echo "  - rm -rf $victim"
      rm -rf -- "$victim"
    done
  done
done

