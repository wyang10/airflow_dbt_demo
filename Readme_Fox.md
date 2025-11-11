# Airflow + dbt + Snowflake 本地演示（含 Postgres 元数据库）🦊🐱

一个稳定、可复现的本地数据编排模板：用 Apache Airflow 调度、dbt 建模、Postgres 作为 Airflow 元数据库、Snowflake 作为数仓。内置一键启动、健康检查、回归验证、数据质量（Great Expectations）与通知（Mailpit）。

核心设计要点
- TaskGroup 封装 dbt run/test，统一传入补数变量 `{start_date,end_date}`，减少样板代码
- 分层流水线（Bronze → Silver → Gold）层间以测试作为质量闸口
- 使用 Airflow Pool `dbt` 串行化 dbt CLI，避免 `target/`、`dbt_packages/` 的并发冲突
- Gold 完成后发布 Dataset：`dbt://gold/fct_orders`，可被下游 DAG 订阅

## 快速开始

前置依赖：Docker Desktop ≥ 4.x、GNU Make、bash、curl

1) 配置凭据（仅本地保存，不入库）
- 复制并编辑 `airflow/.env`（可参考 `airflow/.env.example`），至少填入 Snowflake：`SNOWFLAKE_ACCOUNT`、`SNOWFLAKE_USER`、`SNOWFLAKE_PASSWORD`、`SNOWFLAKE_ROLE`、`SNOWFLAKE_WAREHOUSE`、`SNOWFLAKE_DATABASE`、`SNOWFLAKE_SCHEMA`。
- 示例（占位符示意，勿提交真实密码）：
  ```dotenv
  SNOWFLAKE_ACCOUNT=your_account
  SNOWFLAKE_USER=your_user
  SNOWFLAKE_PASSWORD=your_password
  SNOWFLAKE_ROLE=dbt_role
  SNOWFLAKE_WAREHOUSE=DBT_WH
  SNOWFLAKE_DATABASE=DBT_DB
  SNOWFLAKE_SCHEMA=DBT_SCHEMA
  # 可选：任务失败告警收件人
  ALERT_EMAIL=you@example.com
  ```

2) 启动（任选其一）
- `make up`               # 初始化并启动，自动打开 UI
- `./launch.sh --init`    # 一次性初始化 + 启动
- `make rebuild` / `./launch.sh --rebuild`  # 重新构建镜像后启动
- `make fresh`            # 清理卷后启动（危险）
- 打开 `http://localhost:8080`（用户名/密码：`airflow / airflow`）

3) 验证
- 触发并等待全部示例 DAG 成功：`make validate`
- 或仅验证子集：`make validate-daily` / `make validate-pipelines`

4) 清理历史失败（UI 红点）
- 保留运行记录，仅清失败任务实例：`make clear-failed`
- 直接删除失败的 DAG Run：`make clear-failed-hard`

或快捷指令：
```
./launch.sh --fresh --no-open && make validate
```

## 目录结构

```
./
├─ airflow/                  # Airflow（DAG、容器依赖、.env）
│  ├─ dags/
│  │  ├─ dbt_daily.py
│  │  ├─ dbt_daily_pipeline.py
│  │  ├─ dbt_layered_pipeline.py
│  │  ├─ smtp_smoke.py
│  │  └─ serving/
│  │     ├─ quality_checks.py
│  │     └─ dbt_gold_consumer.py
│  ├─ requirements.txt       # 容器内安装：dbt、GE provider 等
│  └─ .env                   # Snowflake & 可选告警邮箱（已 gitignore）
├─ data_pipeline/            # dbt 项目根目录
│  ├─ dbt_project.yml
│  ├─ profiles.yml           # 从环境变量读取 Snowflake 凭据
│  ├─ models/
│  │  ├─ bronze/
│  │  ├─ silver/
│  │  └─ gold/
│  └─ snippets/              # 可复用模板（sources/tests）
├─ great_expectations/       # GE 配置、校验结果与本地 Data Docs
├─ scripts/                  # 验证、清理、QA、小工具
├─ docker-compose.yml        # Postgres + Airflow + Mailpit + Nginx(GE docs)
├─ Makefile                  # 常用命令（make help）
└─ README.md
```

## 组件与版本

- Airflow 2.9.3（镜像：`apache/airflow:2.9.3-python3.11`）
  - 执行器：LocalExecutor
  - 元数据库：Postgres 15
  - 健康检查：`airflow db check`
- dbt-core 1.10 + dbt-snowflake 1.10（容器内安装）
- Great Expectations 0.18 + Provider（质量检查与 Data Docs）
- Mailpit（本地 SMTP 收件箱，UI: `http://localhost:8025`）
- Nginx 暴露 GE Data Docs（`http://localhost:8081`）

挂载与路径
- `./airflow/dags -> /opt/airflow/dags`
- `./data_pipeline -> /opt/airflow/dbt`
- `./great_expectations -> /opt/airflow/great_expectations`

## 示例 DAG 与运行顺序

- `dbt_layered_pipeline`（推荐阅读）：
  - `dbt_deps → [bronze.run] → [bronze.test] → [silver.run] → [silver.test] → [gold.run] → [gold.test] → 发布 Dataset dbt://gold/fct_orders`
- `dbt_daily_pipeline`：单条流水线，使用 TaskGroup 统一运行 + 测试
- `dbt_daily`：最小化 smoke（`dbt_deps → dbt_run → dbt_test`）
- `dbt_gold_consumer`：订阅 `dbt://gold/fct_orders`，按需运行下游（`tag:downstream`）
- `quality_checks`：运行 GE 的 `daily_metrics_chk`，成功后更新 Data Docs
- `smtp_smoke`：SMTP 冒烟（需设置 `ALERT_EMAIL` 才会发送）

TaskGroup 复用函数位于：`airflow/dags/lib/dbt_groups.py`

## Great Expectations（数据质量）

- 打开本地 Data Docs：`http://localhost:8081`
- 质量 DAG：`quality_checks`（自动调用 `UpdateDataDocsAction` 生成/更新文档）
- Airflow 任务页内的额外链接会把容器内的 `file://...` 自动改写为主机 `http://localhost:8081/...`
- 清理历史 GE 结果（仅保留最近 N 份）：
  - `make prune_ge`（默认保留 5 份）或 `make prune_ge PRUNE_KEEP=10`

## 通知与邮件（内置 Mailpit）

- 开发默认使用 Mailpit：
  - Web UI：`http://localhost:8025`
  - SMTP：`mailpit:1025`（无认证、无 TLS）
- 切换真实 SMTP（示例：Gmail）
  - 在 Airflow UI 创建连接（Admin → Connections → +）：
    - Conn Id: `smtp_gmail`，Type: `smtp`，Host: `smtp.gmail.com`，Port: `587`
    - Login: 你的邮箱；Password: App Password
    - Extra: `{ "starttls": true }`
  - 或使用 CLI 添加连接（参考下方命令），并把 `smtp_smoke` 的 `conn_id` 改为新建连接

CLI 示例（创建 Gmail SMTP 连接）：
```
docker compose exec -T webserver \
  airflow connections add smtp_gmail \
  --conn-type smtp --conn-host smtp.gmail.com --conn-port 587 \
  --conn-login YOU@gmail.com --conn-password 'APP_PASSWORD' \
  --conn-extra '{"starttls": true}'
```

## 本地 dbt 调试（可选）

- 一键准备本地 venv、加载 `airflow/.env` 并自检：`make env`
- 常用命令：
  - `make dbt-debug` / `make dbt-parse` / `make dbt-ls`
  - `make dbt-run-bronze` / `make dbt-run-silver` / `make dbt-run-gold`
  - `make dbt-build`（全量构建 + 测试）
  - `make dbt-docs`（生成 + 本地预览 dbt 文档）

## 常用运维命令

- `make help`           查看所有可用命令
- `make ps`             查看容器状态
- `make logs`           跟随 webserver + scheduler 日志
- `make health`         健康检查（Web/Scheduler）
- `make down`           停止容器（保留卷）
- `make destroy`        停止并删除卷（危险）

## 稳定性约定

- 所有 dbt 任务使用 Pool `dbt`（大小 1）以串行运行 CLI
- DAG 设置 `max_active_runs=1`、默认 1 次重试，减少偶发波动
- 仅运行 `dbt deps` 保持依赖一致，不在任务内清空 `target/` 或 `dbt_packages/`

## 故障排查（FAQ）

- Web 健康检查失败：`curl -fsS http://localhost:8080/health`；重启 Docker 后 `make up`
- 未配置 Snowflake 凭据时，dbt 任务会被 ShortCircuit 跳过（避免长时间失败）
- Airflow UI 红点（历史失败）：`make clear-failed` 或 `make clear-failed-hard`
- GE Provider 未安装导致 `quality_checks` 无任务：容器会自动安装 `airflow-provider-great-expectations`（见 `airflow/requirements.txt`）
- dbt CLI 未找到：容器内 PATH 已包含 `~/.local/bin`；本地调试请先 `make env`

## 安全与机密

- `airflow/.env` 已被 `.gitignore` 忽略，请勿提交真实凭据
- 生产环境推荐将依赖烘焙进镜像，并使用 Secret Manager（Vault/KMS/Secrets Manager）

## 许可证

本项目使用 MIT License，详见根目录 `LICENSE`。
