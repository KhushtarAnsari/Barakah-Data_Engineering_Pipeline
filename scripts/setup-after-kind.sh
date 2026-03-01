#!/usr/bin/env bash
# Run after Kind cluster exists (01-create-cluster.sh done).
# Installs operators, deploys data sources → Kafka → ClickHouse → Airflow, applies CH schema, copies DAG.
# Then: create clickhouse_default connection in Airflow UI (see end of script).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== 1. Strimzi (Kafka) operator ==="
"$SCRIPT_DIR/02-install-strimzi.sh"

echo "=== 2. ClickHouse operator ==="
"$SCRIPT_DIR/03-install-clickhouse-operator.sh"

echo "=== 3. Data sources (PostgreSQL, MongoDB) ==="
"$SCRIPT_DIR/04-deploy-data-sources.sh"

echo "=== 4. Kafka + Debezium Connect ==="
# Build and load Connect image (Strimzi base + Debezium plugins) so pod has kafka_connect_run.sh
"$SCRIPT_DIR/build-connect-image.sh" || { echo "Run: ./scripts/build-connect-image.sh then re-run this script."; exit 1; }
"$SCRIPT_DIR/05-deploy-kafka.sh"

echo "=== 5. ClickHouse cluster ==="
kubectl apply -f "$REPO_ROOT/k8s/clickhouse/clickhouse-installation.yaml"
echo "Waiting for ClickHouse pod..."
sleep 30
kubectl wait --for=condition=Ready pod -l clickhouse.altinity.com/chi=analytics -n clickhouse --timeout=300s || true

echo "=== 6. ClickHouse schema (Kafka engines, silver, gold) ==="
CH_POD=$(kubectl get pod -n clickhouse -l clickhouse.altinity.com/chi=analytics -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -z "$CH_POD" ]; then
  echo "ClickHouse pod not found. Wait a minute and run: kubectl exec -i -n clickhouse \$(kubectl get pod -n clickhouse -l clickhouse.altinity.com/chi=analytics -o jsonpath='{.items[0].metadata.name}') -- clickhouse-client --user=default --password=default --multiquery < $REPO_ROOT/scripts/clickhouse-init.sql"
else
  kubectl exec -i -n clickhouse "$CH_POD" -- clickhouse-client --user=default --password=default --multiquery < "$REPO_ROOT/scripts/clickhouse-init.sql"
  echo "Schema applied."
fi

echo "=== 7. Airflow ==="
helm repo add apache-airflow https://airflow.apache.org 2>/dev/null || true
helm repo update
helm upgrade --install airflow apache-airflow/airflow \
  --namespace airflow \
  --create-namespace \
  -f "$REPO_ROOT/airflow/values.yaml" \
  --wait \
  --timeout 20m \
  || { echo "Airflow install timed out; release is installed but some pods may still be starting. Check: kubectl get pods -n airflow"; }

echo "=== 8. Copy DAG ==="
DAG_COPIED=""
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
  SCHEDULER_POD=$(kubectl get pod -n airflow -l component=scheduler -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  if [ -n "$SCHEDULER_POD" ] && kubectl wait --for=condition=Ready pod/"$SCHEDULER_POD" -n airflow --timeout=30s 2>/dev/null; then
    if kubectl cp "$REPO_ROOT/airflow/dags/gold_user_activity_dag.py" "airflow/$SCHEDULER_POD:/opt/airflow/dags/" -n airflow -c scheduler 2>/dev/null; then
      echo "DAG copied to $SCHEDULER_POD"
      DAG_COPIED=1
      break
    fi
  fi
  sleep 15
done
if [ -z "$DAG_COPIED" ]; then
  echo "DAG not copied yet (scheduler may still be starting). When airflow-scheduler is Running, run:"
  echo "  kubectl cp airflow/dags/gold_user_activity_dag.py airflow/\$(kubectl get pod -n airflow -l component=scheduler -o jsonpath='{.items[0].metadata.name}'):/opt/airflow/dags/ -n airflow -c scheduler"
fi

CH_SVC=$(kubectl get svc -n clickhouse -o name 2>/dev/null | head -1 | sed 's|.*/||')
echo ""
echo "=============================================="
echo "SETUP DONE. Final step (manual):"
echo "=============================================="
echo "1. Port-forward Airflow UI (Airflow 3 uses api-server):"
echo "   kubectl port-forward svc/airflow-api-server 8080:8080 -n airflow"
echo "2. Open http://localhost:8080 (login e.g. admin / admin)."
echo "3. Admin → Connections → Add:"
echo "   Connection Id:  clickhouse_default"
echo "   Connection Type: ClickHouse"
echo "   Host:  $CH_SVC.clickhouse.svc.cluster.local"
echo "   Port:  8123"
echo "   Schema: default"
echo "4. In UI: Dags → gold_user_activity_daily → unpause (toggle) → Trigger DAG"
echo "   If DAGs do not appear, copy the DAG again and check dag-processor/scheduler logs."
echo "=============================================="
