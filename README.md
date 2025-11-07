# Airflow + dbt + Snowflake (Postgres-backed) Demo 🦊🐱

A reproducible, stable local data orchestration template: Apache Airflow for scheduling, dbt for modeling, Postgres as Airflow metadata DB, and Snowflake as the warehouse. Includes one-command startup, health checks, regression validation, and cleanup helpers.

## Quick Start

Prereqs: Docker Desktop ≥ 4.x, GNU Make, bash, curl

1) Credentials (kept local, not committed)
- Create `airflow/.env` (you can copy from `airflow/.env.example`) and fill in Snowflake creds: account, user, password, role, warehouse, database, schema. These envs are passed into containers for dbt to use.

2) Start (choose one mode)
- `./launch.sh --init`      # one-time init + start
- `./launch.sh --rebuild`   # rebuild images (installs deps) + start
- `./launch.sh --upgrade`   # pull latest images and recreate containers
- `./launch.sh --fresh`     # nuke volumes and start clean (dangerous)
- When healthy, open: `http://localhost:8080`
  - User/pass: `airflow / airflow`

3) Validate
- Trigger and wait for all DAGs to succeed: `make validate`
- Or validate a subset: `make validate-daily` / `make validate-pipelines`

4) Clear red dots (historical failures)
- Keep run records, clear failed task instances: `make clear-failed`
- Remove failed runs (destructive): `make clear-failed-hard`

## Layout

```
./
├─ airflow/                  # Airflow (DAGs, container requirements, .env)
│  ├─ dags/
│  │  ├─ dbt_daily.py
│  │  ├─ dbt_pipeline_dag.py
│  │  └─ dbt_layered_pipeline.py
│  ├─ requirements.txt       # installed at container startup via _PIP_ADDITIONAL_REQUIREMENTS
│  └─ .env                   # Snowflake credentials (gitignored)
├─ data_pipeline/            # dbt project root
│  ├─ dbt_project.yml
│  ├─ profiles.yml
│  ├─ models/
│  │  ├─ bronze/
│  │  ├─ silver/
│  │  └─ gold/
│  ├─ snippets/              # copy-paste templates (relationships, sources)
│  └─ .gitignore
├─ scripts/
│  ├─ validate.sh            # trigger + wait for 3 DAGs
│  └─ clear_failed.sh        # clear failed instances / delete failed runs
├─ docker-compose.yml        # Postgres + LocalExecutor root stack
├─ launch.sh                 # one-click bootstrap + health + logs
├─ Makefile                  # handy targets (validate/clear/health)
└─ README.md
```

## Stack & Config

- Airflow 2.9.3 (`apache/airflow:2.9.3-python3.11`)
  - Executor: LocalExecutor
  - Metadata DB: Postgres (`postgres:15-alpine`)
  - Healthcheck: `airflow db check`
- dbt-core 1.10 + dbt-snowflake 1.10 (installed at container start)
- Mounts:
  - `./airflow/dags -> /opt/airflow/dags`
  - `./data_pipeline -> /opt/airflow/dbt`

Compose highlights:
- `airflow-init` runs `airflow db init`, creates `airflow/airflow` user, and a `dbt` pool (size 1)
- Scheduler/Webserver depend on Postgres healthy + init completed

## Runtime Conventions (stability)

- All dbt tasks use Airflow pool `dbt` (size 1) to serialize dbt CLI; avoids `target/` and `dbt_packages/` races
- DAGs use `max_active_runs=1` and one retry by default to reduce flakiness
- No deletion of `dbt_packages/target` in tasks; only `dbt deps` to keep deps consistent

## Common Ops

- Check health
  - `docker compose ps`
  - `curl -fsS http://localhost:8080/health`
- Tail logs
  - `docker compose logs webserver --tail 100 -f`
  - `docker compose logs scheduler --tail 100 -f`
- Trigger / inspect DAGs
  - `docker compose exec -T webserver airflow dags list`
  - `docker compose exec -T webserver airflow dags trigger dbt_daily`
  - `docker compose exec -T webserver airflow dags list-runs -d dbt_daily -o table`

## Email / Notifications (built‑in Mailpit)

- This stack includes a local SMTP sink using Mailpit for easy testing.
  - Web UI: `http://localhost:8025`
  - SMTP host/port (preconfigured): `mailpit:1025` (no auth, no TLS)
- Smoke test DAG: `smtp_smoke`
  - Trigger in UI or run: `docker compose exec -T webserver airflow dags trigger smtp_smoke`
  - Open Mailpit UI to see the test email in the inbox.
- Switching to a real SMTP provider (e.g., Gmail/Mailtrap):
  - Edit `airflow/.env` SMTP variables (see `airflow/.env.example`) and restart services:
    - `docker compose restart webserver scheduler` (or `up -d --force-recreate`)
  - For Gmail, enable 2FA and use an App Password; for development, Mailtrap is recommended.

## Pipeline Differences & Run Order

What’s special in this repo:
- TaskGroup helpers for dbt run/test with backfill vars and pools (`airflow/dags/lib/`)
- Layered pipeline enforces quality gates between layers
- Datasets publish/subscribe from gold completion
- Optional Great Expectations context is mounted and runnable out-of-the-box

Run order (layered example):

```
dbt_deps
  → [bronze.run] → [bronze.test]
  → [silver.run] → [silver.test]
  → [gold.run]   → [gold.test] → publishes Dataset: dbt://gold/fct_orders
```

dbt_daily (smoke) is simpler:

```
dbt_deps → dbt_run → dbt_test → publishes Dataset
```

## Templates (sources/tests)

- See `data_pipeline/snippets/` for new-style relationships (with `arguments`) and a standard source template. Copy and replace placeholders.

## Secrets

- `.env` is gitignored — keep credentials out of the repo
- For production, bake deps into an image and use a secret manager (Vault/KMS/Secrets Manager)

## Troubleshooting

- UI red dots indicate historical failures — use `make clear-failed` to clean up
- If containers restart repeatedly: `./launch.sh --fresh`
- If Docker Desktop misbehaves: restart Docker, then rerun `./launch.sh`
