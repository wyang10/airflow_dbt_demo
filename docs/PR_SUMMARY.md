# Airflow + dbt Demo: Quality, CI, TaskGroups, and GE

This PR introduces:

- Data quality: dbt tests with `severity: error` for core models
- TaskGroups: reusable `dbt_run_group` / `dbt_test_group` to reduce boilerplate
- Backfill-ready: injects `data_interval_start/end` into dbt via `--vars`
- Datasets: publish `dbt://gold/fct_orders` on gold completion; example consumer DAG
- Optional Great Expectations: minimal context + checkpoint, runnable in compose
- CI: ruff + flake8, pytest (DAG import), `dbt parse/compile`
- Dev UX: launch modes `--init | --rebuild | --upgrade`; compose health/depends_on

## How to run

1) Build/Start (choose one)
- `./launch.sh --init`      # one-time init + start
- `./launch.sh --rebuild`   # rebuild images (installs deps) + start
- `./launch.sh --upgrade`   # pull latest images and recreate containers

2) Validate DAGs
- `make validate`                      # trigger and wait for all pipelines
- `make validate-daily`                # smoke DAG only
- `make validate-pipelines`            # layered pipeline DAGs

3) Optional GE
- Rebuild already includes GE deps; run: `airflow dags trigger quality_checks`

## Notable files
- `airflow/dags/lib/dbt_groups.py` — TaskGroup helpers for dbt
- `airflow/dags/dbt_daily.py` — now uses TaskGroups (simple smoke path)
- `airflow/dags/dbt_layered_pipeline.py` — layered pipeline with quality gates
- `great_expectations/*` — minimal GE config + suite + checkpoint
- `.github/workflows/ci.yml` — lint, pytest, dbt compile

