#!/usr/bin/env bash
###
 # @Author: Audrey Yang 97855340+wyang10@users.noreply.github.com
 # @Date: 2025-11-06 01:06:31
 # @LastEditors: Audrey Yang 97855340+wyang10@users.noreply.github.com
 # @LastEditTime: 2025-11-06 11:48:52
 # @FilePath: /airflow_dbt_demo/init_env.sh
 # @Description: 这是默认设置,请设置`customMade`, 打开koroFileHeader查看配置 进行设置: https://github.com/OBKoro1/koro1FileHeader/wiki/%E9%85%8D%E7%BD%AE
### 
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
echo "📁 Project root: $PROJECT_ROOT"

# 1) 本地 dbt 虚拟环境（用于你在宿主机上跑 dbt 命令）
VENV_DIR="$PROJECT_ROOT/data_pipeline/.venv"

# 检查 venv 是否存在以及是否“陈旧/损坏”（例如项目目录被移动导致 shebang 指向旧路径）
broken_venv() {
  # 1) 目录不存在
  [[ -d "$VENV_DIR" ]] || return 0
  # 2) python 可执行不存在
  [[ -x "$VENV_DIR/bin/python" ]] || return 0
  # 3) 试跑一个最简单的命令，失败则认为损坏
  "$VENV_DIR/bin/python" -c 'import sys; assert sys.version_info.major >= 3' >/dev/null 2>&1 || return 0
  # 4) 检查 pip shebang 是否指向当前 venv（目录移动后常见问题）
  local pip_head
  pip_head="$(head -n1 "$VENV_DIR/bin/pip" 2>/dev/null || true)"
  if [[ "$pip_head" == "#!"* ]] && [[ "$pip_head" != "#!$VENV_DIR/"* ]]; then
    return 0
  fi
  return 1 # 不损坏
}

if broken_venv; then
  if [[ -d "$VENV_DIR" ]]; then
    echo "🧹 Removing stale/broken venv ..."
    rm -rf "$VENV_DIR"
  fi
  echo "🐍 Creating Python venv for dbt ..."
  python3 -m venv "$VENV_DIR"
fi

# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"
echo "✅ venv: $VIRTUAL_ENV"

# 可选：如果没装，帮你装 dbt-snowflake
pip show dbt-snowflake >/dev/null 2>&1 || {
  echo "📦 Installing dbt + adapter (local)..."
  pip install -q "dbt-core>=1.10,<2" "dbt-snowflake>=1.10,<2"
}

# 2) 设置 dbt 使用的 profiles 目录
export DBT_PROFILES_DIR="$PROJECT_ROOT/data_pipeline"
echo "🔧 DBT_PROFILES_DIR=$DBT_PROFILES_DIR"

# 3) 批量加载 Snowflake 环境变量（供本地 dbt 调试）
if [[ -f "$PROJECT_ROOT/airflow/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$PROJECT_ROOT/airflow/.env"
  set +a
  echo "🔐 Loaded env from airflow/.env"

  # If the env is configured for containers (e.g. /opt/airflow/secrets/...),
  # remap to a local file under ./secrets/ so `dbt` on the host can still run.
  if [[ -n "${SNOWFLAKE_PRIVATE_KEY_PATH:-}" ]] && [[ ! -f "${SNOWFLAKE_PRIVATE_KEY_PATH}" ]]; then
    key_base="$(basename "${SNOWFLAKE_PRIVATE_KEY_PATH}")"
    local_key="$PROJECT_ROOT/secrets/$key_base"
    if [[ -f "$local_key" ]]; then
      export SNOWFLAKE_PRIVATE_KEY_PATH="$local_key"
      echo "🔑 Remapped SNOWFLAKE_PRIVATE_KEY_PATH -> $SNOWFLAKE_PRIVATE_KEY_PATH (host)"
    fi
  fi
else
  echo "⚠️  Missing: $PROJECT_ROOT/airflow/.env  (请先创建并写入 Snowflake 变量)"
fi

# 4) 打印关键环境变量确认（掩码密码）
echo "🔎 Env check:"
( printenv | grep -E '^(DBT_PROFILES_DIR|DBT_TARGET|SNOWFLAKE_(ACCOUNT|USER|ROLE|WAREHOUSE|DATABASE|SCHEMA))$' || true ) \
  | sed 's/\(SNOWFLAKE_PASSWORD=\).*/\1********/'

# 5) 本地 dbt 自检（可选）
if [[ -z "${SNOWFLAKE_ACCOUNT:-}" ]]; then
  echo "🧪 No Snowflake credentials detected -> running: dbt parse (project=data_pipeline)"
  dbt parse --project-dir "$PROJECT_ROOT/data_pipeline" --profiles-dir "$PROJECT_ROOT/data_pipeline" || true
else
  echo "🧪 Running: dbt debug (project=data_pipeline)"
  dbt debug --project-dir "$PROJECT_ROOT/data_pipeline" --profiles-dir "$PROJECT_ROOT/data_pipeline" || true
fi

cat <<'TIPS'

✅ 环境已就绪！

常用本地命令：
  dbt ls
  dbt run --select path:models/bronze
  dbt run --select path:models/silver
  dbt run --select path:models/gold
  dbt build

下一步（Docker 启动 Airflow）：
  docker compose up -d
  # 打开 http://localhost:8080  （airflow/airflow）

TIPS
