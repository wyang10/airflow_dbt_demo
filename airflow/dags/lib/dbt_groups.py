from __future__ import annotations

from typing import List, Optional

from airflow.decorators import task_group
from airflow.operators.bash import BashOperator
from airflow.datasets import Dataset


def _dbt_cmd(project_dir: str, cmd: str) -> str:
    return f"""
set -euo pipefail
cd {project_dir}
dbt --version || true
# Ensure packages are present to avoid 'Failed to read package' errors
if [ ! -f "dbt_packages/dbt_utils/dbt_project.yml" ]; then
  echo '== Ensuring dbt packages (dbt deps) =='
  dbt deps || true
fi
{cmd}
""".strip()


@task_group
def dbt_run_group(
    selector: str,
    env: dict,
    project_dir: str = "/opt/airflow/dbt",
    outlets_datasets: Optional[List[Dataset]] = None,
    pool: Optional[str] = "dbt",
):
    BashOperator(
        task_id="run",
        bash_command=_dbt_cmd(
            project_dir,
            (
                "dbt run "
                + f"--select '{selector}' "
                + "--vars \"{start_date: '{{ data_interval_start | ds }}', end_date: '{{ data_interval_end | ds }}'}\""
            ),
        ),
        env=env,
        do_xcom_push=False,
        outlets=outlets_datasets or [],
        pool=pool,
    )


@task_group
def dbt_test_group(
    selector: str,
    env: dict,
    project_dir: str = "/opt/airflow/dbt",
    outlets_datasets: Optional[List[Dataset]] = None,
    pool: Optional[str] = "dbt",
):
    BashOperator(
        task_id="test",
        bash_command=_dbt_cmd(
            project_dir,
            (
                "dbt test "
                + f"--select '{selector}' "
                + "--vars \"{start_date: '{{ data_interval_start | ds }}', end_date: '{{ data_interval_end | ds }}'}\""
            ),
        ),
        env=env,
        do_xcom_push=False,
        outlets=outlets_datasets or [],
        pool=pool,
    )
