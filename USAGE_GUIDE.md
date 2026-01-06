# Local Airflow + dbt + Snowflake Demo (Postgres Metadata DB)

Note: `README.md` is for portfolio-style overview; this `USAGE_GUIDE.md` contains full runbook and operational details.

This is a stable, reproducible local data-orchestration template:
- Apache Airflow for scheduling
- dbt for modeling
- Postgres as the Airflow metadata DB
- Snowflake as the warehouse
- Built-in one-command startup, health checks, regression validation, data quality (Great Expectations), and notifications (Mailpit)

Key design points
- Wrap `dbt run/test` in TaskGroups and consistently pass backfill vars `{start_date,end_date}` to reduce boilerplate
- Layered pipeline (Bronze → Silver → Gold) with tests as quality gates between layers
- Serialize dbt CLI via Airflow Pool `dbt` to prevent concurrency conflicts in `target/` and `dbt_packages/`
- Publish Dataset after Gold: `dbt://gold/fct_orders`, which downstream DAGs can subscribe to

## Quickstart

Prereqs: Docker Desktop ≥ 4.x, GNU Make, bash, curl

1) Configure credentials (local only, never committed)
- Copy and edit `airflow/.env` (use `airflow/.env.example` as a template). At minimum fill Snowflake vars:
  - `SNOWFLAKE_ACCOUNT`, `SNOWFLAKE_USER`, `SNOWFLAKE_ROLE`, `SNOWFLAKE_WAREHOUSE`, `SNOWFLAKE_DATABASE`, `SNOWFLAKE_SCHEMA`
- Pick one auth mode:
  - Password: set `SNOWFLAKE_PASSWORD` (default `DBT_TARGET=dev`)
  - Key Pair (recommended when MFA is enforced): set `DBT_TARGET=dev_keypair` + `SNOWFLAKE_PRIVATE_KEY_PATH` (see `data_pipeline/profiles.yml`)
- Example (placeholders only; do not commit real secrets):
  ```dotenv
  SNOWFLAKE_ACCOUNT=your_account
  SNOWFLAKE_USER=your_user
  SNOWFLAKE_PASSWORD=your_password
  SNOWFLAKE_ROLE=dbt_role
  SNOWFLAKE_WAREHOUSE=DBT_WH
  SNOWFLAKE_DATABASE=DBT_DB
  SNOWFLAKE_SCHEMA=DBT_SCHEMA
  # Optional: email recipient for failure alerts
  ALERT_EMAIL=you@example.com
  ```

2) Start (choose one)
- `make up`               # init + start, auto-opens UI
- `./launch.sh --init`    # one-time init + start
- `make rebuild` / `./launch.sh --rebuild`  # rebuild images then start
- `make fresh`            # start clean, delete volumes (dangerous)
- Open `http://localhost:8080` (user/pass: `airflow / airflow`)

3) Validate
- Trigger and wait for all sample DAGs to succeed: `make validate`
- Or validate a subset: `make validate-daily` / `make validate-pipelines`

4) Clear historical failures (red dots in UI)
- Keep run records, clear failed task instances: `make clear-failed`
- Delete failed DAG runs (destructive): `make clear-failed-hard`

Shortcut:
```
./launch.sh --fresh --no-open && make validate
```

## Directory Layout

```
./
├─ airflow/                  # Airflow (DAGs, image deps, .env)
│  ├─ dags/
│  │  ├─ dbt_daily.py
│  │  ├─ dbt_pipeline_dag.py
│  │  ├─ dbt_layered_pipeline.py
│  │  ├─ smtp_smoke.py
│  │  └─ serving/
│  │     ├─ quality_checks.py
│  │     └─ dbt_gold_consumer.py
│  ├─ Dockerfile             # image build (installs dbt + GE provider)
│  ├─ requirements.txt       # dbt, GE provider, etc. installed into image
│  └─ .env                   # Snowflake + optional alert email (gitignored)
├─ data_pipeline/            # dbt project root
│  ├─ dbt_project.yml
│  ├─ profiles.yml           # reads Snowflake creds from env vars
│  ├─ packages.yml           # dbt_utils dependency
│  ├─ models/
│  │  ├─ bronze/
│  │  ├─ silver/
│  │  └─ gold/
│  ├─ snapshots/             # SCD2 / audit history
│  └─ snippets/              # reusable templates (sources/tests)
├─ great_expectations/       # GE config, validations, local Data Docs
├─ scripts/                  # validation, cleanup, QA helpers
├─ docker-compose.yml        # Postgres + Airflow + Mailpit + Nginx(GE docs)
├─ Makefile                  # handy commands (make help)
└─ README.md
```

## Components & Versions

- Airflow 2.9.3 (image built from `apache/airflow:2.9.3-python3.11`)
  - Executor: LocalExecutor
  - Metadata DB: Postgres 15
  - Healthcheck: `airflow db check`
- dbt-core 1.10 + dbt-snowflake 1.10 (installed in the image)
- Great Expectations 0.18 + provider (DQ gate + Data Docs)
- Mailpit (local SMTP sink, UI: `http://localhost:8025`)
- Nginx serves GE Data Docs (`http://localhost:8081`)

Mounts & paths
- `./airflow/dags -> /opt/airflow/dags`
- `./data_pipeline -> /opt/airflow/dbt`
- `./great_expectations -> /opt/airflow/great_expectations`

## Sample DAGs & Run Order

- `dbt_layered_pipeline` (recommended read):
  - `dbt_deps → [bronze.run] → [bronze.test] → [silver.run] → [silver.test] → [gold.run] → [gold.test] → publish Dataset dbt://gold/fct_orders → dbt snapshot (SCD2/audit)`
- `dbt_daily_pipeline`: single-line pipeline using TaskGroups (defined in `airflow/dags/dbt_pipeline_dag.py`)
- `dbt_daily`: minimal smoke (`dbt_deps → dbt_run → dbt_test`)
- `dbt_gold_consumer`: subscribes to `dbt://gold/fct_orders` and runs downstream models (`tag:downstream`)
- `quality_checks`: runs GE checkpoint `daily_metrics_chk` and updates Data Docs
- `smtp_smoke`: SMTP smoke test (requires `ALERT_EMAIL` to actually send)

TaskGroup helpers: `airflow/dags/lib/dbt_groups.py`

## Great Expectations (Data Quality)

- Local Data Docs: `http://localhost:8081`
- DAG: `quality_checks` (runs `UpdateDataDocsAction` to generate/update docs)
- `quality_checks` exports `fct_orders` to: `/opt/airflow/great_expectations/uncommitted/data/fct_orders.csv`, then runs the checkpoint
- Airflow task extra link rewrites container `file://...` URLs to host `http://localhost:8081/...`
- Prune historical GE outputs (keep last N):
  - `make prune_ge` (default keep 5) or `make prune_ge PRUNE_KEEP=10`

## Governance & Audit (dbt snapshots / SCD Type 2)

- Snapshots live in: `data_pipeline/snapshots/`
- `dbt_layered_pipeline` runs `dbt snapshot` after Gold tests pass, to record historical changes for dims/policies (SCD2)
- Where to find them in Snowflake: under `<SNOWFLAKE_SCHEMA>` (same as the dbt target/schema)

## Notifications & Email (Mailpit included)

- Dev default uses Mailpit:
  - Web UI: `http://localhost:8025`
  - SMTP: `mailpit:1025` (no auth, no TLS)
- Switch to a real SMTP (example: Gmail)
  - Create a connection in Airflow UI (Admin → Connections → +):
    - Conn Id: `smtp_gmail`, Type: `smtp`, Host: `smtp.gmail.com`, Port: `587`
    - Login: your email; Password: App Password
    - Extra: `{ "starttls": true }`
  - Or add via CLI and update `smtp_smoke` to use your `conn_id`:

CLI example (create Gmail SMTP connection):
```
docker compose exec -T webserver \
  airflow connections add smtp_gmail \
  --conn-type smtp --conn-host smtp.gmail.com --conn-port 587 \
  --conn-login YOU@gmail.com --conn-password 'APP_PASSWORD' \
  --conn-extra '{"starttls": true}'
```

## Local dbt Debugging (Optional)

- One command to set up local venv, load `airflow/.env`, and run a quick check: `make env`
- Useful targets:
  - `make dbt-debug` / `make dbt-parse` / `make dbt-ls`
  - `make dbt-run-bronze` / `make dbt-run-silver` / `make dbt-run-gold`
  - `make dbt-build` (full build + tests)
  - `make dbt-docs` (generate + serve dbt docs locally)

## Common Ops Commands

- `make help`           list available commands
- `make ps`             container status
- `make logs`           follow webserver + scheduler logs
- `make health`         health check (Web/Scheduler)
- `make down`           stop containers (keep volumes)
- `make destroy`        stop and delete volumes (dangerous)

## Stability Conventions

- All dbt tasks use Pool `dbt` (size 1) to serialize CLI execution
- DAGs set `max_active_runs=1` and default to 1 retry to reduce flakiness
- Keep deps consistent with `dbt deps`; do not delete `target/` or `dbt_packages/` inside tasks

## Troubleshooting (FAQ)

- Web health fails: `curl -fsS http://localhost:8080/health`; restart Docker, then `make up`
- If Snowflake creds are not configured, dbt tasks are ShortCircuited to avoid noisy failures
- Red dots in UI (historical failures): `make clear-failed` or `make clear-failed-hard`
- If `quality_checks` shows no tasks because GE provider is missing: it is installed via `airflow/requirements.txt`
- If dbt CLI is not found: container PATH includes `~/.local/bin`; for local dev, run `make env` first

## Security & Secrets

- `airflow/.env` is gitignored — do not commit real credentials
- For production, bake dependencies into images and use a Secret Manager (Vault/KMS/Secrets Manager)

## License

MIT License — see `LICENSE` at the repo root.
