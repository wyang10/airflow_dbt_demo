"""Run Great Expectations suites against critical tables.

This DAG requires the Great Expectations provider. If it's not installed,
the DAG is created paused with no tasks so the module still parses.
"""

from datetime import datetime
from airflow import DAG
from airflow.utils.context import Context
from airflow.operators.empty import EmptyOperator


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
        # Rewrite GE file:// URL to the exposed http://localhost:8081 path for UI extra link
        ti = context.get("ti")
        try:
            url = ti.xcom_pull(key="data_docs_url")
        except Exception:
            url = None
        prefix = "/opt/airflow/great_expectations/uncommitted/data_docs/local_site/"
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

    with DAG(
        dag_id="quality_checks",
        start_date=datetime(2025, 11, 1),
        schedule=None,  # Airflow 2.4+ 使用 schedule；老版本请改回 schedule_interval=None
        catchup=False,
        description="Run Great Expectations suites against critical tables",
        tags=["quality", "ge"],
    ) as dag:
        # 占位上游任务
        start = EmptyOperator(task_id="start")

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

        start >> run_ge >> publish

    return dag


globals()["quality_checks"] = _build_dag_with_ge()