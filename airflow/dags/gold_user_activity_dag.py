"""
Daily DAG: join silver_users and silver_events -> gold_user_activity.
Idempotent and backfill-safe: for each run we process the logical date (previous day),
delete any existing rows for that date, then insert aggregated data.
Uses BashOperator + ClickHouse HTTP so no extra provider is required (works with Airflow 3).
"""
from datetime import datetime, timedelta

from airflow import DAG
from airflow.providers.standard.operators.bash import BashOperator

# ClickHouse HTTP endpoint (from inside cluster; Altinity operator creates svc clickhouse-analytics)
# Auth: must match CHI configuration.users.default/password (we set "default" in clickhouse-installation.yaml)
CH_BASE = "http://clickhouse-analytics.clickhouse.svc.cluster.local:8123"
CH_PASSWORD = "default"

default_args = {
    "owner": "data-engineering",
    "depends_on_past": False,
    "email_on_failure": False,
    "email_on_retry": False,
    "retries": 2,
    "retry_delay": timedelta(minutes=2),
}

with DAG(
    dag_id="gold_user_activity_daily",
    default_args=default_args,
    description="Daily aggregation: silver_users + silver_events -> gold_user_activity (idempotent)",
    schedule="0 1 * * *",  # 01:00 daily
    start_date=datetime(2025, 1, 1),
    catchup=True,
    tags=["gold", "analytics"],
) as dag:

    _auth = "?user=default" + ("&password=" + CH_PASSWORD if CH_PASSWORD else "")
    _url = CH_BASE + _auth

    delete_existing = BashOperator(
        task_id="delete_existing_for_date",
        bash_command=(
            "curl -s '"
            + _url
            + "' --data-binary \"ALTER TABLE gold_user_activity DELETE WHERE activity_date = '{{ ds }}'\""
        ),
    )

    insert_aggregated = BashOperator(
        task_id="insert_aggregated_activity",
        bash_command=(
            "curl -s '"
            + _url
            + "' --data-binary \"INSERT INTO gold_user_activity (activity_date, user_id, total_events, last_event_ts) "
            "SELECT toDate(e.event_ts) AS activity_date, e.user_id, count() AS total_events, max(e.event_ts) AS last_event_ts "
            "FROM silver_events e INNER JOIN (SELECT user_id FROM silver_users FINAL WHERE _deleted = 0) u ON e.user_id = u.user_id "
            "WHERE toDate(e.event_ts) = '{{ ds }}' GROUP BY activity_date, e.user_id\""
        ),
    )

    delete_existing >> insert_aggregated
