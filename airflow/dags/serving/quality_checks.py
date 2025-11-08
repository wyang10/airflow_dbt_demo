"""
Optional Great Expectations checks.

If the GE Airflow provider is installed, run an example validation.
Otherwise, this DAG parses but is paused and contains no tasks.
"""
from datetime import datetime

from airflow import DAG


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

    with DAG(
        dag_id="quality_checks",
        start_date=datetime(2025, 11, 1),
        schedule=None,
        catchup=False,
        description="Run Great Expectations suites against critical tables",
        tags=["quality", "ge"],
    ) as dag:
        # This assumes a GE context is present under /opt/airflow/great_expectations
        # and an expectation suite named "daily_metrics" with a checkpoint "daily_metrics_chk".
        # You can adapt names to your setup.
        run_ge = GreatExpectationsOperator(
            task_id="run_daily_metrics_suite",
            data_context_root_dir="/opt/airflow/great_expectations",
            checkpoint_name="daily_metrics_chk",
            fail_task_on_validation_failure=True,
        )

    return dag


globals()["quality_checks"] = _build_dag_with_ge()
