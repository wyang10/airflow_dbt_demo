# Modern ELT Pipeline with Embedded Data Quality at Scale
## Airflow · dbt · Snowflake · Great Expectations · Docker · CI/CD

This repo is intended for data engineers who want a production-like ELT template with orchestration, modeling, and quality gates. It is structured to show:
- orchestration patterns
- modeling patterns
- quality gates
- governance/audit mechanisms

## Overview

This project builds a layered ELT pipeline on Snowflake (using Snowflake sample TPCH tables for easy onboarding):
- **Airflow** orchestrates dbt run/test/snapshot with TaskGroups, pools, and dataset-driven triggers
- **dbt** models a star schema (dims + facts) with incremental builds and SCD2 snapshots
- **Great Expectations** runs a DQ checkpoint as a gate and publishes Data Docs

Highlights
- Built reusable TaskGroups wrapping dbt run/test with backfill vars `{start_date,end_date}` to reduce boilerplate.
- Designed a layered ELT pipeline (Bronze → Silver → Gold) with tests as quality gates between layers.
- Serialized dbt CLI runs via Airflow Pool `dbt` to prevent `target/` and `dbt_packages/` race conditions.
- Published dataset `dbt://gold/fct_orders` for downstream Datasets-based orchestration.
- Integrated Great Expectations as automated data quality validation.

A stable, reproducible local data orchestration template: Apache Airflow for scheduling, dbt for modeling, Postgres as the Airflow metadata DB, and Snowflake as the warehouse. Comes with one‑command startup, health checks, regression validation, Great Expectations data quality, and Mailpit for notifications.


## Architecture (High-level)

![Layered pipeline](tests/demo/architecture.png)

## Repository Map / Project Layout

```
.
├── airflow/
│   ├── dags/
│   │   ├── dbt_daily.py                   # smoke: deps → run → test
│   │   ├── dbt_pipeline_dag.py            # DAG id: dbt_daily_pipeline (deps → run → test + Dataset)
│   │   ├── dbt_layered_pipeline.py        # Bronze→Silver→Gold gates + dbt snapshot
│   │   ├── smtp_smoke.py                  # SMTP smoke test (Mailpit by default)
│   │   ├── serving/
│   │   │   ├── quality_checks.py          # Great Expectations gate
│   │   │   └── dbt_gold_consumer.py       # Dataset consumer example
│   │   └── lib/
│   │       ├── dbt_groups.py              # reusable TaskGroups for dbt run/test
│   │       └── creds.py                   # Snowflake creds short-circuit
│   ├── Dockerfile                         # Airflow image (installs dbt + GE provider)
│   ├── requirements.txt                   # pip deps baked into the image
│   └── .env.example                       # copy to airflow/.env (local secrets)
│
├── data_pipeline/                          # dbt project root
│   ├── dbt_project.yml
│   ├── profiles.yml                        # reads Snowflake creds from env vars
│   ├── packages.yml                        # dbt_utils dependency
│   ├── models/
│   │   ├── bronze/
│   │   ├── silver/
│   │   └── gold/
│   ├── snapshots/                          # SCD2 / audit history
│   └── snippets/                           # copy-ready templates
│
├── great_expectations/                     # GE project + Data Docs
├── scripts/                                # validation, cleanup, QA helpers
├── secrets/                                # local-only (gitignored)
├── docker-compose.yml                      # Postgres + Airflow + Mailpit + Nginx(GE docs)
├── Makefile                                # handy local commands
├── init_env.sh                             # local dbt env bootstrapper
├── launch.sh                               # one-command runner (wraps docker compose)
├── README.md
├── README_cv.md
└── USAGE_GUIDE.md
```

## Patterns → Code

**Orchestration patterns**
- TaskGroups wrapping dbt run/test: `airflow/dags/lib/dbt_groups.py`
- Layered pipeline (Bronze → Silver → Gold + gates + snapshots): `airflow/dags/dbt_layered_pipeline.py`
- Dataset-driven downstream trigger example: `airflow/dags/serving/dbt_gold_consumer.py`
- Pools for serialization: created by compose init (Pool name `dbt`)

**Modeling patterns**
- dbt project root: `data_pipeline/`
- Bronze staging: `data_pipeline/models/bronze/`
- Silver intermediate: `data_pipeline/models/silver/`
- Gold marts (facts + dims): `data_pipeline/models/gold/`

**Quality gates**
- dbt tests as layer gates (run/test split per layer): `airflow/dags/dbt_layered_pipeline.py`
- dbt tests (schema + relationships + business rules): `data_pipeline/models/**/**.yml`
- Great Expectations checkpoint + Data Docs: `airflow/dags/serving/quality_checks.py`
  - Checkpoint: `great_expectations/checkpoints/daily_metrics_chk.yml`
  - Suite: `great_expectations/expectations/daily_metrics.json`

**Governance / audit**
- SCD Type 2 snapshots (dbt snapshots): `data_pipeline/snapshots/`
- Snapshot execution in Airflow: `airflow/dags/dbt_layered_pipeline.py`

## Data Modeling (Star Schema + SLA/Policy Demo)

Key Gold models:
- Dimensions: `data_pipeline/models/gold/dim_customer.sql`, `data_pipeline/models/gold/dim_part.sql`, `data_pipeline/models/gold/dim_supplier.sql`, `data_pipeline/models/gold/dim_date.sql`
- Facts:
  - `data_pipeline/models/gold/fct_order_items.sql` (incremental + clustering)
  - `data_pipeline/models/gold/fct_shipment_events.sql` (incremental + SLA flags)
  - `data_pipeline/models/gold/fct_orders.sql` (published as Airflow Dataset `dbt://gold/fct_orders`)
- Policies (demo governance targets): `data_pipeline/models/gold/dim_sla_policy.sql`, `data_pipeline/models/gold/dim_status_policy.sql`


## Quickstart

Prerequisites: Docker Desktop ≥ 4.x, GNU Make, bash, curl

1) Credentials (local only, not committed)
- Copy `airflow/.env.example` to `airflow/.env` and fill Snowflake vars: `SNOWFLAKE_ACCOUNT`, `SNOWFLAKE_USER`, `SNOWFLAKE_PASSWORD`, `SNOWFLAKE_ROLE`, `SNOWFLAKE_WAREHOUSE`, `SNOWFLAKE_DATABASE`, `SNOWFLAKE_SCHEMA`.
- Optional: `ALERT_EMAIL` for failure notifications.

2) Start (pick one)
- `make up`                 # init + start, opens the UI
- `./launch.sh --init`      # one‑time init + start
- `make rebuild` or `./launch.sh --rebuild`  # rebuild images then start
- `make fresh`              # start clean, delete volumes (dangerous)
- Open `http://localhost:8080` (user/pass: `airflow / airflow`)

3) Validate
- Trigger and wait for sample DAGs to succeed: `make validate`
- Or a subset: `make validate-daily` / `make validate-pipelines`

4) Clear historical failures (red dots in UI)
- Keep run records, clear failed task instances: `make clear-failed`
- Delete failed runs (destructive): `make clear-failed-hard`

Or Simply Start:
```
./launch.sh --fresh --no-open && make validate
```
Tested on macOS 14 / Ubuntu 22.04 environments.


Useful local UIs:
- Airflow: `http://localhost:8080`
- Great Expectations Data Docs: `http://localhost:8081`
- Mailpit (SMTP UI): `http://localhost:8025`

Full setup/ops (Snowflake MFA/keypair auth, troubleshooting, etc.): `USAGE_GUIDE.md`

## Screenshots

Airflow DAGs  
![Airflow Dags](tests/demo/airflow.png)

Great Expectations Data Docs  
![GE Docs](tests/demo/ge.png)

CI/CD overview  
![Docker + CICD](tests/demo/cicd.png)

## License

MIT — see `LICENSE`.
