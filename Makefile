# Makefile — Airflow + dbt + Snowflake 快捷操作台
# 放置路径：项目根目录（含 docker-compose.yml / init_env.sh）
# 用法：make help

SHELL := /bin/bash
PROJECT_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
COMPOSE := docker compose -f $(PROJECT_ROOT)/docker-compose.yml
AIRFLOW_URL ?= http://localhost:8080
AIRFLOW_UID ?= $(shell id -u)

OPEN := open
ifeq ($(shell command -v xdg-open >/dev/null 2>&1; echo $$?),0)
  OPEN := xdg-open
endif

.PHONY: help ########## 默认帮助
help: ## 显示可用命令
	@echo ""
	@echo "🌈 Airflow + dbt + Snowflake 指令小抄"
	@echo ""
	@awk 'BEGIN {FS":.*##"; printf "%-28s %s\n","命令","说明"; printf "%-28s %s\n","----","----"} /^[a-zA-Z0-9_.-]+:.*##/ { printf "%-28s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo ""

# ---------------------------
# 环境初始化 / 本地 dbt
# ---------------------------
.PHONY: env
env:  ## 一键初始化本地环境（source init_env.sh）
	@test -x "$(PROJECT_ROOT)/init_env.sh" || { echo "❌ 找不到 init_env.sh 或无执行权限"; exit 1; }
	@source "$(PROJECT_ROOT)/init_env.sh"

.PHONY: dbt-debug
dbt-debug: env ## dbt debug 自检
	@cd "$(PROJECT_ROOT)/data_pipeline" && dbt debug

.PHONY: dbt-parse
dbt-parse: env ## dbt parse（解析项目）
	@cd "$(PROJECT_ROOT)/data_pipeline" && dbt parse

.PHONY: dbt-ls
dbt-ls: env ## 列出所有模型
	@cd "$(PROJECT_ROOT)/data_pipeline" && dbt ls

.PHONY: dbt-ls-bronze dbt-ls-silver dbt-ls-gold
dbt-ls-bronze: env ## 列出 bronze 模型
	@cd "$(PROJECT_ROOT)/data_pipeline" && dbt ls --select 'path:models/bronze'
dbt-ls-silver: env ## 列出 silver 模型
	@cd "$(PROJECT_ROOT)/data_pipeline" && dbt ls --select 'path:models/silver'
dbt-ls-gold:   env ## 列出 gold 模型
	@cd "$(PROJECT_ROOT)/data_pipeline" && dbt ls --select 'path:models/gold'

.PHONY: dbt-run-bronze dbt-run-silver dbt-run-gold dbt-build
dbt-run-bronze: env ## 仅跑 bronze
	@cd "$(PROJECT_ROOT)/data_pipeline" && dbt run --select 'path:models/bronze'
dbt-run-silver: env ## 仅跑 silver
	@cd "$(PROJECT_ROOT)/data_pipeline" && dbt run --select 'path:models/silver'
dbt-run-gold:   env ## 仅跑 gold
	@cd "$(PROJECT_ROOT)/data_pipeline" && dbt run --select 'path:models/gold'
dbt-build:      env ## 全量构建（含测试）
	@cd "$(PROJECT_ROOT)/data_pipeline" && dbt build

.PHONY: dbt-docs
dbt-docs: env ## 生成 + 本地预览文档（前台）
	@cd "$(PROJECT_ROOT)/data_pipeline" && dbt docs generate && dbt docs serve

# ---------------------------
# Docker / Airflow 管理
# ---------------------------
.PHONY: up rebuild fresh logs down destroy ps open
up:  ## 启动（含初始化），自动打开浏览器
	@AIRFLOW_UID=$(AIRFLOW_UID) $(COMPOSE) run --rm airflow-init
	@AIRFLOW_UID=$(AIRFLOW_UID) $(COMPOSE) up -d
	@$(MAKE) open

rebuild: ## 重新构建镜像并启动
	@AIRFLOW_UID=$(AIRFLOW_UID) $(COMPOSE) build --pull
	@$(MAKE) up

fresh: ## 清卷重起（危险：会删除卷）
	@AIRFLOW_UID=$(AIRFLOW_UID) $(COMPOSE) down -v || true
	@$(MAKE) up

logs: ## 跟随 webserver & scheduler 日志
	@$(COMPOSE) logs -f webserver scheduler

down: ## 停止容器（保留卷）
	@$(COMPOSE) down

destroy: ## 停止容器 + 删除卷 + 清理缓存（危险操作）
	@$(COMPOSE) down -v || true
	@docker system prune -af || true

ps: ## 查看容器状态
	@$(COMPOSE) ps

open: ## 打开 Airflow UI
	@echo "打开 $(AIRFLOW_URL) ..."
	@$(OPEN) "$(AIRFLOW_URL)" >/dev/null 2>&1 || true

# ---------------------------
# 回归/验证
# ---------------------------
.PHONY: validate validate-daily validate-pipelines
validate: ## 一键触发并等待全部 DAG 成功（dbt_daily + pipelines）
	@bash scripts/validate.sh

validate-daily: ## 仅验证 dbt_daily
	@bash scripts/validate.sh dbt_daily

validate-pipelines: ## 仅验证两个 pipeline DAG
	@bash scripts/validate.sh dbt_daily_pipeline dbt_layered_pipeline

.PHONY: clear-failed clear-failed-hard
clear-failed: ## 清理三条 DAG 的失败任务实例（保留运行记录）
	@bash scripts/clear_failed.sh

clear-failed-hard: ## 删除三条 DAG 的失败运行（危险：会删除失败 run 记录）
	@bash scripts/clear_failed.sh --delete-runs

# ---------------------------
# Airflow 运维便捷命令
# ---------------------------
.PHONY: logs-web logs-sch restart-sch clear-queue
logs-web: ## 仅跟随 webserver 日志
	@$(COMPOSE) logs -f webserver
logs-sch: ## 仅跟随 scheduler 日志
	@$(COMPOSE) logs -f scheduler

restart-sch: ## 重启 scheduler
	@$(COMPOSE) restart scheduler

clear-queue: ## 清空 worker/scheduler 队列缓存（必要时）
	@$(COMPOSE) exec -T scheduler bash -lc "airflow jobs check --job-type SchedulerJob || true; rm -rf /opt/airflow/logs/* || true; echo 'queue cleared.'"

# ---------------------------
# 快捷健康检查
# ---------------------------
.PHONY: health
health: ## 健康检查（Airflow Web / Scheduler）
	@echo "Check webserver health..."
	@curl -fsS "$(AIRFLOW_URL)/health" || { echo "❌ webserver unhealthy"; exit 1; }
	@echo "✅ webserver healthy"
	@echo "Check scheduler logs (last 50 lines)..."
	@$(COMPOSE) logs scheduler --tail 50
.PHONY: qa
qa: ## 零门槛本地 QA（parse + build + docs）
	@bash scripts/qa.sh
