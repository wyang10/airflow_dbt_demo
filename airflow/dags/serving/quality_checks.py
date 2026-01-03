"""Run Great Expectations suites against critical tables.

This DAG requires the Great Expectations provider. If it's not installed,
the DAG is created paused with no tasks so the module still parses.
"""

from datetime import datetime
from airflow import DAG
from airflow.utils.context import Context
from airflow.operators.empty import EmptyOperator
from airflow.operators.python import PythonOperator, ShortCircuitOperator

from lib.creds import has_snowflake_creds


def _build_dag_with_ge() -> DAG:
    try:
        from great_expectations_provider.operators.great_expectations import (
            GreatExpectationsOperator,
        )
    except Exception:  # pragma: no cover
        # Provider not available; return an empty, paused DAG
        return DAG(
            dag_id="quality_checks",
            start_date=datetime(2025, 11, 1),
            schedule_interval=None,
            catchup=False,
            is_paused_upon_creation=True,
            description="Great Expectations provider not installed; skipping",
        )

    def _set_docs_http_url(context: Context):
        # Rewrite GE file:// URLs to http://localhost:8081
        # so the clickable extra link still works outside the container
        ti = context.get("ti")
        try:
            url = ti.xcom_pull(key="data_docs_url")
        except Exception:
            url = None
        prefix = (
            "/opt/airflow/great_expectations/uncommitted/data_docs/"
            "local_site/"
        )
        if isinstance(url, str):
            if url.startswith("file://"):
                path = url[len("file://"):]
            else:
                path = url
            if path.startswith(prefix):
                rel = path[len(prefix):]
                http_url = f"http://localhost:8081/{rel}"
            else:
                http_url = "http://localhost:8081/index.html"
        else:
            http_url = "http://localhost:8081/index.html"
        ti.xcom_push(key="data_docs_url", value=http_url)

    def _export_fct_orders_csv():
        import csv
        import os

        import snowflake.connector

        out_path = (
            "/opt/airflow/great_expectations/uncommitted/data/fct_orders.csv"
        )

        connect_kwargs = {
            "account": os.environ.get("SNOWFLAKE_ACCOUNT"),
            "user": os.environ.get("SNOWFLAKE_USER"),
            "role": os.environ.get("SNOWFLAKE_ROLE") or None,
            "warehouse": os.environ.get("SNOWFLAKE_WAREHOUSE") or None,
            "database": os.environ.get("SNOWFLAKE_DATABASE") or None,
            "schema": os.environ.get("SNOWFLAKE_SCHEMA") or None,
        }

        private_key_file = os.environ.get("SNOWFLAKE_PRIVATE_KEY_PATH", "")
        if private_key_file:
            passphrase = os.environ.get(
                "SNOWFLAKE_PRIVATE_KEY_PASSPHRASE", ""
            )
            from cryptography.hazmat.primitives import serialization

            with open(private_key_file, "rb") as f:
                pkey = serialization.load_pem_private_key(
                    f.read(),
                    password=passphrase.encode() if passphrase else None,
                )
            connect_kwargs["private_key"] = pkey.private_bytes(
                encoding=serialization.Encoding.DER,
                format=serialization.PrivateFormat.PKCS8,
                encryption_algorithm=serialization.NoEncryption(),
            )
        else:
            connect_kwargs["password"] = os.environ.get(
                "SNOWFLAKE_PASSWORD"
            )

        # Remove unset values to avoid connector complaints.
        connect_kwargs = {k: v for k, v in connect_kwargs.items() if v}

        conn = snowflake.connector.connect(**connect_kwargs)
        try:
            cur = conn.cursor()
            try:
                cur.execute(
                    """
select
  order_date,
  items_cnt,
  gross_item_sales_amount,
  item_discount_amount
from fct_orders
order by order_date desc
"""
                )
                rows = cur.fetchall()
            finally:
                cur.close()
        finally:
            conn.close()

        os.makedirs(os.path.dirname(out_path), exist_ok=True)
        with open(out_path, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(
                [
                    "order_date",
                    "items_cnt",
                    "gross_item_sales_amount",
                    "item_discount_amount",
                ]
            )
            writer.writerows(rows)

    with DAG(
        dag_id="quality_checks",
        start_date=datetime(2025, 11, 1),
        # Airflow 2.4+ 使用 schedule；老版本请改回
        # schedule_interval=None
        schedule=None,
        catchup=False,
        description="Run Great Expectations suites against critical tables",
        tags=["quality", "ge"],
    ) as dag:
        # 占位上游任务
        start = EmptyOperator(task_id="start")

        check_creds = ShortCircuitOperator(
            task_id="check_snowflake_creds",
            python_callable=has_snowflake_creds,
        )

        export_csv = PythonOperator(
            task_id="export_fct_orders_csv",
            python_callable=_export_fct_orders_csv,
        )

        run_ge = GreatExpectationsOperator(
            task_id="run_daily_metrics_suite",
            data_context_root_dir="/opt/airflow/great_expectations",
            checkpoint_name="daily_metrics_chk",
            fail_task_on_validation_failure=True,
            return_json_dict=True,
            on_success_callback=_set_docs_http_url,
        )

        # 占位下游任务
        publish = EmptyOperator(task_id="publish")

        start >> check_creds >> export_csv >> run_ge >> publish

    return dag


globals()["quality_checks"] = _build_dag_with_ge()
