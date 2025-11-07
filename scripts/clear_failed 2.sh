#!/usr/bin/env bash
set -euo pipefail

# Clear failed task instances or delete failed dag runs for given DAGs.
# Usage: scripts/clear_failed.sh [--delete-runs] [DAG_ID...]

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE="docker compose -f \"$PROJECT_ROOT/docker-compose.yml\""
DELETE_RUNS=0

if [[ "${1:-}" == "--delete-runs" ]]; then
  DELETE_RUNS=1; shift || true
fi

if [[ $# -eq 0 ]]; then
  DAGS=(dbt_daily dbt_daily_pipeline dbt_layered_pipeline)
else
  DAGS=("$@")
fi

for d in "${DAGS[@]}"; do
  echo "🔎 Checking failed runs for $d ..."
  runs=$(eval "$COMPOSE exec -T webserver airflow dags list-runs -d \"$d\" -o json" | jq -r '.[] | select(.state=="failed") | .run_id' 2>/dev/null) || true
  if [[ -z "$runs" ]]; then
    echo "✅ No failed runs for $d"; continue
  fi
  if [[ "$DELETE_RUNS" -eq 1 ]]; then
    echo "$runs" | while read -r r; do
      echo "🗑  Deleting run $d / $r"; eval "$COMPOSE exec -T webserver airflow dags delete-run -d \"$d\" -r \"$r\"" || true
    done
  else
    echo "🧹 Clearing failed task instances for $d"
    eval "$COMPOSE exec -T webserver airflow tasks clear -y \"$d\" --only-failed" || true
  fi
done

echo "Done."
