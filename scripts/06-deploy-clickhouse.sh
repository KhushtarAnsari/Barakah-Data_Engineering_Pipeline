#!/usr/bin/env bash
# Deploy ClickHouse (CHI) and apply schema
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

kubectl apply -f "$REPO_ROOT/k8s/clickhouse/clickhouse-installation.yaml"
echo "Waiting for ClickHouse to be ready..."
sleep 30
kubectl wait --for=condition=Ready pod -l clickhouse.altinity.com/chi=analytics -n clickhouse --timeout=300s || true

echo "Port-forward ClickHouse 8123 to run schema init (in another terminal):"
echo "  kubectl port-forward svc/clickhouse-analytics 8123:8123 -n clickhouse"
echo "Then: clickhouse-client --host localhost --user=default --password=default --multiquery < scripts/clickhouse-init.sql"
echo "Or: CH_POD=\$(kubectl get pod -n clickhouse -l clickhouse.altinity.com/chi=analytics -o jsonpath='{.items[0].metadata.name}'); kubectl exec -i -n clickhouse \$CH_POD -- clickhouse-client --user=default --password=default --multiquery < scripts/clickhouse-init.sql"
echo "ClickHouse deployed."
