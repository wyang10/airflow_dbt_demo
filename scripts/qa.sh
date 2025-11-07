#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "🌱 Preparing local dbt environment ..."
if [[ -x "$PROJECT_ROOT/init_env.sh" ]]; then
  # shellcheck disable=SC1090
  source "$PROJECT_ROOT/init_env.sh"
else
  echo "⚠️  init_env.sh not found; assuming dbt is available on PATH"
fi

cd "$PROJECT_ROOT/data_pipeline"

echo "🔎 dbt parse"
dbt parse

echo "🏗  dbt build (models + tests)"
dbt build

echo "📚 dbt docs generate"
dbt docs generate

echo "✅ QA complete"

