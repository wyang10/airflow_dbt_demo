from airflow import DAG
from airflow.operators.python import ShortCircuitOperator
from airflow.operators.email import EmailOperator
from datetime import datetime
import os


def _has_alert_email() -> bool:
    return bool(os.environ.get("ALERT_EMAIL"))


default_args = {
    "owner": "airflow",
    "start_date": datetime(2025, 11, 1),
    "email_on_failure": True,
}


with DAG(
    dag_id="smtp_smoke",
    default_args=default_args,
    schedule_interval="@once",
    catchup=False,
    is_paused_upon_creation=True,
    tags=["smtp", "notifications"],
) as dag:

    check_email = ShortCircuitOperator(
        task_id="check_alert_email",
        python_callable=_has_alert_email,
    )

    send_test = EmailOperator(
        task_id="send_test_email",
        to=[os.environ.get("ALERT_EMAIL", "")],
        subject="SMTP smoke test: {{ dag.dag_id }} at {{ ts }}",
        html_content="""
            <h3>SMTP smoke test</h3>
            <p>Sent by Airflow DAG <b>{{ dag.dag_id }}</b> at <code>{{ ts }}</code>.</p>
        """,
        conn_id="smtp_mailpit",
    )

    check_email >> send_test
