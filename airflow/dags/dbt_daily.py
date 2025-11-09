"""dbt_daily — Minimal smoke pipeline for dbt.

Architecture:
- dbt_deps -> dbt_run -> dbt_test
- Pool "dbt" serializes CLI runs to avoid target/ races
- Only light metadata via ENV; no large XCom payloads
"""

from airflow import DAG
from airflow.datasets import Dataset
from airflow.operators.bash import BashOperator
from airflow.operators.python import ShortCircuitOperator
from datetime import datetime, timedelta
import os

from lib.creds import has_snowflake_creds
from lib.dbt_groups import dbt_run_group, dbt_test_group


def g(k):
    return os.environ.get(k, "")


# 统一的 ENV（两条 DAG 完全一致）
env_vars = {
    "DBT_PROFILES_DIR": "/opt/airflow/dbt",
    # Traceability: pass query tag to Snowflake via dbt profile
    # Format: dag:task:run_id:queue:ts:try:run_type
    "DBT_QUERY_TAG": (
        "{{ dag.dag_id }}:"
        "{{ task_instance.task_id }}:"
        "{{ dag_run.run_id if dag_run else '' }}:"
        "{{ task_instance.queue if task_instance and "
        "task_instance.queue else 'default' }}:"
        "{{ ts_nodash }}:"
        "{{ task_instance.try_number if task_instance else '' }}:"
        "{{ dag_run.run_type if dag_run else '' }}"
    ),
    "SNOWFLAKE_ACCOUNT": g("SNOWFLAKE_ACCOUNT"),
    "SNOWFLAKE_USER": g("SNOWFLAKE_USER"),
    "SNOWFLAKE_PASSWORD": g("SNOWFLAKE_PASSWORD"),
    "SNOWFLAKE_ROLE": g("SNOWFLAKE_ROLE"),
    "SNOWFLAKE_DATABASE": g("SNOWFLAKE_DATABASE"),
    "SNOWFLAKE_WAREHOUSE": g("SNOWFLAKE_WAREHOUSE"),
    "SNOWFLAKE_SCHEMA": g("SNOWFLAKE_SCHEMA"),
    # 关键：补齐 PATH，确保 `dbt` 能被 BashOperator 找到
    "PATH": "/home/airflow/.local/bin:/usr/local/bin:/usr/bin:/bin",
}

alert_email = g("ALERT_EMAIL")
default_args = {
    "owner": "airflow",
    "start_date": datetime(2025, 11, 1),
    "retries": 1,
    "retry_delay": timedelta(minutes=2),
    "email": [e for e in [alert_email] if e],
    "email_on_failure": True,
}

# 统一的 Bash 片段（加了健壮性与可观测性）
DBT_ENV_CHECK = r"""
set -euo pipefail
cd /opt/airflow/dbt

echo '== ENV CHECK =='
env | grep -E 'SNOWFLAKE_|DBT_|^PATH=' \
  | sed 's/^SNOWFLAKE_PASSWORD=.*/SNOWFLAKE_PASSWORD=********/' \
  || true
which dbt || true
dbt --version || true
"""

with DAG(
    dag_id="dbt_daily",
    default_args=default_args,
    schedule_interval="@daily",
    catchup=False,
    max_active_runs=1,
    tags=["dbt", "snowflake", "smoke"],
) as dag:

    # Skip dbt tasks when Snowflake credentials are not provided locally
    check_creds = ShortCircuitOperator(
        task_id="check_snowflake_creds",
        python_callable=has_snowflake_creds,
    )

    dbt_deps = BashOperator(
        task_id="dbt_deps",
        bash_command=DBT_ENV_CHECK + r"""
dbt deps
""",
        env=env_vars,
        pool="dbt",
    )

    # Smoke line: run everything in project once per day
    # Use TaskGroups to keep structure simple but consistent
    dbt_run = dbt_run_group(
        selector="path:models/bronze path:models/silver path:models/gold",
        env=env_vars,
        project_dir="/opt/airflow/dbt",
        pool="dbt",
    )

    # Quality gate: must pass tests before completing the DAG
    dbt_test = dbt_test_group(
        selector="path:models/bronze path:models/silver path:models/gold",
        env=env_vars,
        project_dir="/opt/airflow/dbt",
        outlets_datasets=[Dataset("dbt://gold/fct_orders")],
        pool="dbt",
    )

    check_creds >> dbt_deps >> dbt_run >> dbt_test
