#!/usr/bin/env bash
set -euo pipefail

# =============== Config ===============
PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
COMPOSE_FILE="$PROJECT_ROOT/docker-compose.yml"
AIRFLOW_PORT="${AIRFLOW_PORT:-8080}"
AIRFLOW_URL="${AIRFLOW_URL:-http://localhost:${AIRFLOW_PORT}}"
PROJECT_NAME="${PROJECT_NAME:-${COMPOSE_PROJECT_NAME:-}}"
OPEN_CMD="open"
command -v xdg-open >/dev/null 2>&1 && OPEN_CMD="xdg-open"
export AIRFLOW_UID="${AIRFLOW_UID:-$(id -u)}"   # for volume permissions
# =====================================

bold(){ printf "\033[1m%s\033[0m\n" "$*"; }
info(){ echo "👉 $*"; }
ok(){ echo "✅ $*"; }
warn(){ echo "⚠️  $*"; }
err(){ echo "❌ $*" >&2; }

usage() {
  cat <<USAGE
Usage: $(basename "$0") [options]

Options:
  --init        One-time initialize Airflow metadata, create admin, and start
  --rebuild     Rebuild images, then start (installs deps via requirements.txt)
  --upgrade     Pull latest images and recreate containers
  --fresh       Stop & remove volumes, then start clean
  --logs        Tail webserver & scheduler logs after start
  --down        Stop and remove containers (keep volumes)
  --destroy     Stop and remove containers + volumes + builder cache
  --project X   Set compose project name (equiv: COMPOSE_PROJECT_NAME)
  --no-open     Do not open browser automatically
  -h, --help    Show this help

Env overrides:
  AIRFLOW_URL     ($AIRFLOW_URL)
  AIRFLOW_UID     ($AIRFLOW_UID)
USAGE
}

# -------------- Args --------------
DO_INIT=0
REBUILD=0
UPGRADE=0
FRESH=0
TAIL_LOGS=0
DO_DOWN=0
DO_DESTROY=0
NO_OPEN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --init) DO_INIT=1; shift ;;
    --rebuild) REBUILD=1; shift ;;
    --upgrade) UPGRADE=1; shift ;;
    --fresh) FRESH=1; shift ;;
    --logs) TAIL_LOGS=1; shift ;;
    --down) DO_DOWN=1; shift ;;
    --destroy) DO_DESTROY=1; shift ;;
    --no-open) NO_OPEN=1; shift ;;
    --project)
      PROJECT_NAME="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) err "Unknown option: $1"; usage; exit 2 ;;
  esac
done

# -------------- Pre-flight checks --------------
need() { command -v "$1" >/dev/null 2>&1 || { err "Missing: $1"; exit 1; }; }
need docker
need docker compose

[[ -f "$COMPOSE_FILE" ]] || { err "docker-compose.yml not found at $COMPOSE_FILE"; exit 1; }

# -------------- Helpers --------------
compose() {
  local args=( -f "$COMPOSE_FILE" )
  if [[ -n "$PROJECT_NAME" ]]; then
    args=( -p "$PROJECT_NAME" "${args[@]}" )
  fi
  docker compose "${args[@]}" "$@"
}

wait_for_web() {
  local timeout=180
  local start_ts
  start_ts=$(date +%s)
  info "Waiting for Airflow webserver at $AIRFLOW_URL ..."
  until curl -fsS "$AIRFLOW_URL/health" >/dev/null 2>&1; do
    sleep 2
    if (( $(date +%s) - start_ts > timeout )); then
      warn "Timed out waiting for webserver. Showing recent webserver logs:"
      compose logs webserver --tail=80 || true
      return 1
    fi
  done
  ok "Airflow webserver is healthy."
}

open_ui() {
  [[ "$NO_OPEN" -eq 1 ]] && return 0
  info "Opening $AIRFLOW_URL ..."
  "$OPEN_CMD" "$AIRFLOW_URL" >/dev/null 2>&1 || warn "Unable to open browser automatically."
}

# -------------- Sub-commands --------------
if [[ "$DO_DOWN" -eq 1 ]]; then
  bold "Stopping Airflow (containers only) ..."
  compose down
  ok "Stopped."
  exit 0
fi

if [[ "$DO_DESTROY" -eq 1 ]]; then
  bold "Destroying all (containers + volumes + cache) ..."
  compose down -v || true
  docker system prune -af || true
  ok "Destroyed."
  exit 0
fi

# -------------- Init local env --------------
bold "Initializing local dbt environment ..."
if [[ -x "$PROJECT_ROOT/init_env.sh" ]]; then
  # shellcheck disable=SC1090
  source "$PROJECT_ROOT/init_env.sh" || true
else
  warn "init_env.sh not found or not executable. Skipping local env init."
fi

# -------------- Start stack --------------
if [[ "$FRESH" -eq 1 ]]; then
  bold "Fresh start: stopping & removing volumes ..."
  compose down -v || true
fi

if [[ "$UPGRADE" -eq 1 ]]; then
  bold "Upgrading images and recreating containers ..."
  compose pull
  compose up -d --force-recreate --remove-orphans
elif [[ "$REBUILD" -eq 1 ]]; then
  bold "Rebuilding images ..."
  compose build --pull
  compose run --rm airflow-init
  compose up -d
elif [[ "$DO_INIT" -eq 1 ]]; then
  bold "Initializing Airflow metadata and starting services ..."
  compose run --rm airflow-init
  compose up -d
else
  bold "Starting Airflow services ..."
  compose run --rm airflow-init
  compose up -d
fi

compose ps

# -------------- Health & Logs --------------
wait_for_web || warn "Web health check did not pass (continuing)."
open_ui

if [[ "$TAIL_LOGS" -eq 1 ]]; then
  bold "Tailing logs (Ctrl+C to stop) ..."
  compose logs -f scheduler webserver
else
  ok "All set. Visit $AIRFLOW_URL (user: airflow / pass: airflow)"
  info "Useful commands:"
  cat <<'CMDS'
  export AIRFLOW_PORT=${AIRFLOW_PORT}
  export COMPOSE_PROJECT_NAME=${PROJECT_NAME}
  docker compose ps
  docker compose logs webserver --tail 100 -f
  docker compose logs scheduler --tail 100 -f
  docker compose restart scheduler
  docker compose down
  # Project helpers
  make validate
  make clear-failed
  AIRFLOW_PORT=9090 ./launch.sh --rebuild
  ./launch.sh --project myairflow --fresh
  ./launch.sh --logs
  ./launch.sh --down
  AIRFLOW_PORT=9090 ./launch.sh --no-open
CMDS
fi
