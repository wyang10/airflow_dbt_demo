# Contributing

Thanks for your interest! This repo is a lightweight, reproducible demo for Airflow + dbt + Snowflake. PRs and issues are welcome.

## Getting started
- Install Docker Desktop, GNU Make.
- Copy `airflow/.env.example` to `airflow/.env` and fill in Snowflake/SMTP credentials.
- Start stack: `./launch.sh --fresh --no-open`
- Validate DAGs: `make validate`
- Local dbt QA: `make qa`

## Pull requests
- Keep changes small and focused, prefer incremental PRs.
- Include a short description of the problem and the solution.
- If touching DAGs/dbt models, run `make validate` (DAGs) and `make qa` (dbt) locally.
- No secrets in PRs — `.env` is gitignored; use env examples only.

## Coding style
- Python (Airflow DAGs): prefer simple, explicit code; avoid heavy abstractions.
- dbt: follow directory layers (bronze/silver/gold) and use new-style `tests:` blocks.
- Shell: `set -euo pipefail` and clear logging.

## Reporting issues
- Use the issue templates and include:
  - What you tried, expected vs actual
  - Relevant logs (webserver/scheduler/dbt)
  - Environment (OS, Docker, Airflow/dbt versions)

## License
- Unless otherwise stated, contributions are under the same license as this repo.
