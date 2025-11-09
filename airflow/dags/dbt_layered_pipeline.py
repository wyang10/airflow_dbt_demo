# airflow/dags/dbt_layered_pipeline.py
# Bronze → Silver → Gold 多层串联（dbt-core + Snowflake）
# 目录假设：
#   /opt/airflow/dbt  -> 你的 dbt 项目根（profiles.yml 也在这里）
#
# 选择器说明（按目录选择）：
#   'path:models/bronze' / 'path:models/silver' / 'path:models/gold'
#
# 如果你更喜欢一次性“构建+测试”，把 USE_DBT_BUILD 设为 True

from datetime import datetime, timedelta
import os

from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.datasets import Dataset
from airflow.operators.python import ShortCircuitOperator
from lib.dbt_groups import dbt_run_group, dbt_test_group
from lib.creds import has_snowflake_creds


# ---------- 可按需修改 ----------
# 容器内 dbt 项目根（与 docker-compose 挂载一致）
DBT_PROJECT_DIR = "/opt/airflow/dbt"
# 通常与项目根同路径
DBT_PROFILES_DIR = "/opt/airflow/dbt"
# 可用 .env 或容器 ENV 指定
DBT_TARGET = os.environ.get("DBT_TARGET", "prod")
# 使用 run+test 拆分以体现“质量闸门”
USE_DBT_BUILD = False
# 每日 03:00 UTC 触发
SCHEDULE_CRON = "0 3 * * *"
START_DATE = datetime(2025, 11, 1)
RETRIES = 1
RETRY_DELAY = timedelta(minutes=5)
# --------------------------------


def _g(k: str, default: str = "") -> str:
    """安全读取环境变量（空值不报错）"""
    return os.environ.get(k, default)


# 透传运行 dbt 所需的关键 ENV
# * 这里不硬编码敏感值；由 docker-compose/.env 注入容器，再原样透传给任务
INTERVAL_VARS = (
    "--vars \"{start_date: '{{ data_interval_start | ds }}', "
    "end_date: '{{ data_interval_end | ds }}'}\""
)


ENV_VARS = {
    # dbt 需要
    "DBT_PROFILES_DIR": DBT_PROFILES_DIR,
    "DBT_TARGET": DBT_TARGET,
    # Traceability tag visible in Snowflake QUERY_HISTORY
    # dag:task:run_id:queue:ts:try:run_type
    "DBT_QUERY_TAG": (
        "{{ dag.dag_id }}:"
        "{{ task_instance.task_id }}:"
        "{{ dag_run.run_id if dag_run else '' }}:"
        "{{ task_instance.queue if task_instance and "
        "task_instance.queue else 'default' }}:"
        "{{ ts_nodash }}:"
        "{{ task_instance.try_number if task_instance else '' }}:"
        "{{ dag_run.run_type if dag_run else '' }}"
    ),

    # Snowflake 凭据（来自宿主 .env -> 容器环境）
    "SNOWFLAKE_ACCOUNT": _g("SNOWFLAKE_ACCOUNT"),
    "SNOWFLAKE_USER": _g("SNOWFLAKE_USER"),
    "SNOWFLAKE_PASSWORD": _g("SNOWFLAKE_PASSWORD"),
    "SNOWFLAKE_ROLE": _g("SNOWFLAKE_ROLE"),
    "SNOWFLAKE_DATABASE": _g("SNOWFLAKE_DATABASE"),
    "SNOWFLAKE_WAREHOUSE": _g("SNOWFLAKE_WAREHOUSE"),
    "SNOWFLAKE_SCHEMA": _g("SNOWFLAKE_SCHEMA"),

    # 让 `dbt` 可执行（某些镜像下 PATH 可能缺少用户 bin）
    "PATH": _g(
        "PATH",
        "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
    ),
}


def dbt_cmd(cmd: str) -> str:
    """统一的 dbt 执行包装：切目录 + 打印版本 + 执行命令"""
    return f"""
set -euo pipefail
cd {DBT_PROJECT_DIR}
echo "==> Using dbt: $(dbt --version)"
{cmd}
""".strip()


def mk_layer_tasks(dag: DAG, layer: str):
    selector = f"path:models/{layer}"
    if USE_DBT_BUILD:
        # Keep build path as a single BashOperator for completeness
        build = BashOperator(
            task_id=f"{layer}_build",
            bash_command=dbt_cmd(
                "dbt build " + f"--select '{selector}' " + INTERVAL_VARS
            ),
            env=ENV_VARS,
            dag=dag,
            pool="dbt",
            do_xcom_push=False,
        )
        return build, None
    # Use TaskGroups (dbt run/test) as quality gates per layer
    run_grp = dbt_run_group(
        selector=selector,
        env=ENV_VARS,
        project_dir=DBT_PROJECT_DIR,
        pool="dbt",
    )
    test_grp = dbt_test_group(
        selector=selector,
        env=ENV_VARS,
        project_dir=DBT_PROJECT_DIR,
        pool="dbt",
    )
    run_grp >> test_grp
    return run_grp, test_grp


alert_email = _g("ALERT_EMAIL")
default_args = {
    "owner": "airflow",
    "start_date": START_DATE,
    "retries": RETRIES,
    "retry_delay": RETRY_DELAY,
    "email": [e for e in [alert_email] if e],
    "email_on_failure": True,
}


with DAG(
    dag_id="dbt_layered_pipeline",
    default_args=default_args,
    schedule_interval=SCHEDULE_CRON,
    catchup=False,
    max_active_runs=1,
    description="Bronze → Silver → Gold 分层 dbt 编排（Snowflake）",
) as dag:

    # 在本地未配置 Snowflake 凭据时跳过 dbt 任务，避免长时间失败
    check_creds = ShortCircuitOperator(
        task_id="check_snowflake_creds",
        python_callable=has_snowflake_creds,
    )

    # 0) dbt 依赖（每次 run 之前拉取，确保包一致）
    dbt_deps = BashOperator(
        task_id="dbt_deps",
        bash_command=dbt_cmd("dbt deps"),
        env=ENV_VARS,
        pool="dbt",
    )

    # 0.1) 如需 seed（可选，默认关闭）
    # dbt_seed = BashOperator(
    #     task_id="dbt_seed",
    #     bash_command=dbt_cmd("dbt seed --full-refresh"),
    #     env=ENV_VARS,
    # )

    # 1) Bronze
    bronze_main, bronze_test = mk_layer_tasks(dag, "bronze")

    # 2) Silver
    silver_main, silver_test = mk_layer_tasks(dag, "silver")

    # 3) Gold
    gold_main, gold_test = mk_layer_tasks(dag, "gold")
    # Publish dataset when gold tests pass
    if gold_test:
        gold_test.outlets = [Dataset("dbt://gold/fct_orders")]

    # 串联：deps -> (seed) -> bronze -> silver -> gold
    chain_head = check_creds >> dbt_deps
    # chain_head = dbt_deps >> dbt_seed  # 若启用 seed，改用此行

    chain_head >> bronze_main >> silver_main >> gold_main

    # 若使用 run+test 分开，则把 test 也串上（build 模式下 test 任务为 None）
    if bronze_test:
        bronze_main >> bronze_test >> silver_main
    if silver_test:
        silver_main >> silver_test >> gold_main
    if gold_test:
        gold_main >> gold_test
