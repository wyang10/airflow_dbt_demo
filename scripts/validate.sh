#!/usr/bin/env bash
set -euo pipefail

# One-click DAG validation against the running compose stack.
# Usage: scripts/validate.sh [dbt_daily dbt_daily_pipeline dbt_layered_pipeline]

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="$PROJECT_ROOT/docker-compose.yml"

compose() { docker compose -f "$COMPOSE_FILE" "$@"; }

wait_dag() {
  local dag_id="$1"; shift || true

  # Wait until DAG is loaded (up to 60s)
  for i in {1..60}; do
    if compose exec -T webserver airflow dags list -o json | jq -r '.[].dag_id' | grep -qx "$dag_id"; then
      break
    fi
    sleep 2
    if [[ $i -eq 60 ]]; then echo "⚠️  DAG $dag_id not loaded"; return 2; fi
  done

  echo "👉 Triggering $dag_id ..."
  compose exec -T webserver airflow dags unpause "$dag_id" >/dev/null || true
  compose exec -T webserver airflow dags trigger "$dag_id" >/dev/null

  # Wait until a run appears
  local run_id=""
  for i in {1..30}; do
    run_id=$(compose exec -T webserver airflow dags list-runs -d "$dag_id" -o json | jq -r '.[0].run_id' 2>/dev/null || true)
    [[ -n "$run_id" && "$run_id" != null ]] && break || true
    sleep 2
  done
  echo "⏳ Waiting for $dag_id (${run_id:-pending}) ..."

  local timeout=900 # 15m
  local start_ts=$(date +%s)
  while true; do
    local state
    state=$(compose exec -T webserver airflow dags list-runs -d "$dag_id" -o json | jq -r '.[0].state' 2>/dev/null || echo "")
    printf "."; sleep 3
    if [[ "$state" == "success" ]]; then
      echo "\n✅ $dag_id (${run_id:-latest}) -> SUCCESS"; return 0
    elif [[ "$state" == "failed" ]]; then
      echo "\n❌ $dag_id (${run_id:-latest}) -> FAILED"; return 1
    fi
    if (( $(date +%s) - start_ts > timeout )); then
      echo "\n⚠️  $dag_id (${run_id:-latest}) -> TIMEOUT"; return 2
    fi
  done
}

main() {
  # Friendly guard for missing env file used by compose
  if [[ ! -f "$PROJECT_ROOT/airflow/.env" ]]; then
    echo "❌ Missing $PROJECT_ROOT/airflow/.env (compose env_file)" >&2
    echo "   Fix: cp airflow/.env.example airflow/.env; then fill SNOWFLAKE_* (or leave blanks if only running GE)." >&2
    exit 2
  fi
  local dags
  if [[ $# -eq 0 ]]; then
    dags=(dbt_daily dbt_daily_pipeline dbt_layered_pipeline)
  else
    dags=("$@")
  fi
  local rc=0

  # Health check webserver first
  if ! curl -fsS "http://localhost:8080/health" >/dev/null 2>&1; then
    echo "⚠️  Webserver not healthy at http://localhost:8080/health — is the stack up?" >&2
  fi

  for d in "${dags[@]}"; do
    if ! wait_dag "$d"; then rc=1; fi
  done
  exit "$rc"
}

main "$@"
