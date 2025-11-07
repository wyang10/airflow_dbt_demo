from airflow import DAG
from airflow.datasets import Dataset
from lib.dbt_groups import dbt_run_group, dbt_test_group
from airflow.operators.bash import BashOperator
from datetime import datetime, timedelta
import os

def g(k): 
    return os.environ.get(k, "")

# 与 dbt_daily 完全一致的 ENV
env_vars = {
    "DBT_PROFILES_DIR": "/opt/airflow/dbt",
    # dag:task:run_id:queue:ts:try:run_type
    "DBT_QUERY_TAG": "{{ dag.dag_id }}:{{ task_instance.task_id }}:{{ dag_run.run_id if dag_run else '' }}:{{ task_instance.queue if task_instance and task_instance.queue else 'default' }}:{{ ts_nodash }}:{{ task_instance.try_number if task_instance else '' }}:{{ dag_run.run_type if dag_run else '' }}",
    "SNOWFLAKE_ACCOUNT":  g("SNOWFLAKE_ACCOUNT"),
    "SNOWFLAKE_USER":     g("SNOWFLAKE_USER"),
    "SNOWFLAKE_PASSWORD": g("SNOWFLAKE_PASSWORD"),
    "SNOWFLAKE_ROLE":     g("SNOWFLAKE_ROLE"),
    "SNOWFLAKE_DATABASE": g("SNOWFLAKE_DATABASE"),
    "SNOWFLAKE_WAREHOUSE":g("SNOWFLAKE_WAREHOUSE"),
    "SNOWFLAKE_SCHEMA":   g("SNOWFLAKE_SCHEMA"),
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

DBT_ENV_CHECK = r"""
set -euo pipefail
cd /opt/airflow/dbt

echo '== ENV CHECK =='
env | grep -E 'SNOWFLAKE_|DBT_|^PATH=' | sed 's/^SNOWFLAKE_PASSWORD=.*/SNOWFLAKE_PASSWORD=********/' || true
which dbt || true
dbt --version || true
"""

with DAG(
    dag_id="dbt_daily_pipeline",
    default_args=default_args,
    schedule_interval="0 3 * * *",  # 每天 03:00
    catchup=False,
    max_active_runs=1,
    tags=["dbt", "snowflake"],
) as dag:

    dbt_deps = BashOperator(
        task_id="dbt_deps",
        bash_command=DBT_ENV_CHECK + r"""
dbt deps
""",
        env=env_vars,
        pool="dbt",
    )

    # Use reusable TaskGroups for dbt run/test
    run_grp = dbt_run_group(
        selector="path:models",
        env=env_vars,
        project_dir="/opt/airflow/dbt",
        pool="dbt",
    )

    test_grp = dbt_test_group(
        selector="path:models",
        env=env_vars,
        project_dir="/opt/airflow/dbt",
        outlets_datasets=[Dataset("dbt://gold/fct_orders")],
        pool="dbt",
    )

    dbt_deps >> run_grp >> test_grp
