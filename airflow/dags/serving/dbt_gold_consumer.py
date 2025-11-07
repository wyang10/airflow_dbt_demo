from datetime import datetime, timedelta
import os

from airflow import DAG
from airflow.datasets import Dataset
from airflow.operators.bash import BashOperator


def _g(k: str, default: str = "") -> str:
    return os.environ.get(k, default)


ENV_VARS = {
    "DBT_PROFILES_DIR": "/opt/airflow/dbt",
    "SNOWFLAKE_ACCOUNT": _g("SNOWFLAKE_ACCOUNT"),
    "SNOWFLAKE_USER": _g("SNOWFLAKE_USER"),
    "SNOWFLAKE_PASSWORD": _g("SNOWFLAKE_PASSWORD"),
    "SNOWFLAKE_ROLE": _g("SNOWFLAKE_ROLE"),
    "SNOWFLAKE_DATABASE": _g("SNOWFLAKE_DATABASE"),
    "SNOWFLAKE_WAREHOUSE": _g("SNOWFLAKE_WAREHOUSE"),
    "SNOWFLAKE_SCHEMA": _g("SNOWFLAKE_SCHEMA"),
}


with DAG(
    dag_id="dbt_gold_consumer",
    start_date=datetime(2025, 11, 1),
    schedule=[Dataset("dbt://gold/fct_orders")],
    catchup=False,
    default_args={
        "owner": "airflow",
        "retries": 0,
        "retry_delay": timedelta(minutes=1),
    },
    tags=["dbt", "datasets", "downstream"],
) as dag:
    run_downstream = BashOperator(
        task_id="run_downstream",
        bash_command=(
            "set -euo pipefail\n"
            "cd /opt/airflow/dbt\n"
            "dbt run --select 'tag:downstream' "
            "--vars \"{start_date: '{{ data_interval_start | ds }}', end_date: '{{ data_interval_end | ds }}'}\"\n"
        ),
        env=ENV_VARS,
        do_xcom_push=False,
    )

