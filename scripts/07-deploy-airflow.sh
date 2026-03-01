#!/usr/bin/env bash
# Deploy Airflow via Helm
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

helm repo add apache-airflow https://airflow.apache.org
helm repo update
helm upgrade --install airflow apache-airflow/airflow \
  --namespace airflow \
  --create-namespace \
  -f "$REPO_ROOT/airflow/values.yaml" \
  --wait \
  --timeout 20m

echo "Copy DAGs into scheduler (shared dags volume with DAG processor):"
POD=$(kubectl get pod -n airflow -l component=scheduler -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$POD" ]; then
  for f in gold_user_activity_dag.py test_hello_dag.py; do
    [ -f "$REPO_ROOT/airflow/dags/$f" ] && kubectl cp "$REPO_ROOT/airflow/dags/$f" "airflow/$POD:/opt/airflow/dags/" -n airflow -c scheduler && echo "  Copied $f"
  done
  echo "If 'airflow dags list' shows No data found, ensure DAG processor is running and copy the DAG again; check dag-processor logs."
fi
echo "Airflow deployed. Set connection clickhouse_default to your ClickHouse host (e.g. clickhouse-analytics.clickhouse.svc.cluster.local:8123)."
