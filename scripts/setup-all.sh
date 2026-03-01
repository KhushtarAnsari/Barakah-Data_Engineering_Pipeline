#!/usr/bin/env bash
# Full setup in order: cluster -> operators -> data sources -> Kafka -> ClickHouse -> Airflow
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== 1. Kind cluster ==="
"$SCRIPT_DIR/01-create-cluster.sh"
echo "=== 2. Strimzi operator ==="
"$SCRIPT_DIR/02-install-strimzi.sh"
echo "=== 3. ClickHouse operator ==="
"$SCRIPT_DIR/03-install-clickhouse-operator.sh"
echo "=== 4. Data sources (PostgreSQL, MongoDB) ==="
"$SCRIPT_DIR/04-deploy-data-sources.sh"
echo "=== 5. Kafka + Debezium Connect ==="
"$SCRIPT_DIR/build-connect-image.sh" || { echo "Run ./scripts/build-connect-image.sh then re-run 05 or setup-all."; exit 1; }
"$SCRIPT_DIR/05-deploy-kafka.sh"
echo "=== 6. ClickHouse ==="
"$SCRIPT_DIR/06-deploy-clickhouse.sh"
echo "=== 7. Airflow ==="
"$SCRIPT_DIR/07-deploy-airflow.sh"

echo "Setup complete. See README for ClickHouse schema init and Airflow connection."
