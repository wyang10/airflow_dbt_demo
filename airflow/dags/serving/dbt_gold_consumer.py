from datetime import datetime, timedelta
import os

from airflow import DAG
from airflow.datasets import Dataset
from airflow.operators.bash import BashOperator
from airflow.operators.python import ShortCircuitOperator
from lib.creds import has_snowflake_creds


def _g(k: str, default: str = "") -> str:
    return os.environ.get(k, default)


INTERVAL_VARS = (
    "--vars \"{start_date: '{{ data_interval_start | ds }}', "
    "end_date: '{{ data_interval_end | ds }}'}\""
)


ENV_VARS = {
    "DBT_PROFILES_DIR": "/opt/airflow/dbt",
    "DBT_TARGET": _g("DBT_TARGET", "dev"),
    "SNOWFLAKE_ACCOUNT": _g("SNOWFLAKE_ACCOUNT"),
    "SNOWFLAKE_USER": _g("SNOWFLAKE_USER"),
    "SNOWFLAKE_PASSWORD": _g("SNOWFLAKE_PASSWORD"),
    "SNOWFLAKE_PRIVATE_KEY_PATH": _g("SNOWFLAKE_PRIVATE_KEY_PATH"),
    "SNOWFLAKE_PRIVATE_KEY_PASSPHRASE": _g("SNOWFLAKE_PRIVATE_KEY_PASSPHRASE"),
    "SNOWFLAKE_OAUTH_TOKEN": _g("SNOWFLAKE_OAUTH_TOKEN"),
    "SNOWFLAKE_ROLE": _g("SNOWFLAKE_ROLE"),
    "SNOWFLAKE_DATABASE": _g("SNOWFLAKE_DATABASE"),
    "SNOWFLAKE_WAREHOUSE": _g("SNOWFLAKE_WAREHOUSE"),
    "SNOWFLAKE_SCHEMA": _g("SNOWFLAKE_SCHEMA"),
    "PATH": _g("PATH", "/home/airflow/.local/bin:/usr/local/bin:/usr/bin:/bin"),
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
    check_creds = ShortCircuitOperator(
        task_id="check_snowflake_creds",
        python_callable=has_snowflake_creds,
    )

    run_downstream = BashOperator(
        task_id="run_downstream",
        bash_command=(
            "set -euo pipefail\n"
            "cd /opt/airflow/dbt\n"
            # Skip gracefully if no downstream models are tagged
            "if ! dbt ls --select 'tag:downstream' | grep -q .; then "
            "echo 'No models with tag:downstream; skipping.'; exit 0; fi\n"
            "dbt run --select 'tag:downstream' "
            + INTERVAL_VARS
            + "\n"
        ),
        env=ENV_VARS,
        do_xcom_push=False,
    )
    check_creds >> run_downstream
