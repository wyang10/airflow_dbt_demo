# AIRFLOW_DBT_DEMO/airflow/Dockerfile
FROM apache/airflow:2.9.3-python3.11

USER root
# 安装 git，并清理缓存
RUN apt-get update && apt-get install -y --no-install-recommends git \
    && git --version \
    && rm -rf /var/lib/apt/lists/*

USER airflow
COPY requirements.txt /requirements.txt
RUN python -m pip install --upgrade pip \
    && python -m pip install --no-cache-dir -r /requirements.txt

ENV PATH="/home/airflow/.local/bin:${PATH}"
ENV DBT_PROFILES_DIR=/opt/airflow/dbt
