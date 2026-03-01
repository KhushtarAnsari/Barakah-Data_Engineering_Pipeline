#!/usr/bin/env bash
# Diagnose and fix: data in Kafka but not in ClickHouse silver tables.
# ClickHouse Kafka engine consumes in the background (no fixed interval; usually seconds).
# Direct SELECT on Kafka tables is disabled in ClickHouse 26+; the MV is fed by background consumption.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CH_POD=$(kubectl get pod -n clickhouse -l clickhouse.altinity.com/chi=analytics -o jsonpath='{.items[0].metadata.name}' 2>/dev/null) || true
# Use broker pod (name contains -pool- or -kafka-), not entity-operator
KAFKA_POD=$(kubectl get pods -n kafka --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null | grep -E 'data-engineering-kafka-(pool-a|kafka)-[0-9]+' | head -1) || true

if [[ -z "$CH_POD" ]]; then echo "No ClickHouse pod"; exit 1; fi
if [[ -z "$KAFKA_POD" ]]; then echo "No Kafka broker pod (expected data-engineering-kafka-pool-a-0)"; exit 1; fi

CH_Q() { kubectl exec -n clickhouse "$CH_POD" -- clickhouse-client --user=default --password=default -q "$1" 2>/dev/null; }

echo "=== 1. Kafka topics (broker pod: $KAFKA_POD) ==="
for topic in postgres.public.users mongo.commerce.events; do
  if kubectl exec -n kafka "$KAFKA_POD" -- bin/kafka-topics.sh --bootstrap-server localhost:9092 --list 2>/dev/null | grep -q "^${topic}$"; then
    echo "  Topic $topic exists"
  else
    echo "  Topic $topic not found - deploy connectors and ensure PG/Mongo have data"
  fi
done

echo ""
echo "=== 2. Silver table row counts (ClickHouse consumes Kafka in background) ==="
CH_Q "SELECT 'silver_users' AS tbl, count() AS cnt FROM silver_users"
CH_Q "SELECT 'silver_events' AS tbl, count() AS cnt FROM silver_events"

SU=$(CH_Q "SELECT count() FROM silver_users" 2>/dev/null | tr -d ' ')
SE=$(CH_Q "SELECT count() FROM silver_events" 2>/dev/null | tr -d ' ')
if [[ "${SU:-0}" = "0" ]] || [[ "${SE:-0}" = "0" ]]; then
  echo ""
  echo "=== 3. Silver empty: applying reset (new consumer groups). Background consumption will fill silver in a few seconds. ==="
  kubectl exec -i -n clickhouse "$CH_POD" -- clickhouse-client --user=default --password=default --multiquery < "$REPO_ROOT/scripts/clickhouse-kafka-reset-consumer-groups.sql"
  echo "  Waiting 15s for background consumption..."
  sleep 15
  echo "  silver_users count: $(CH_Q "SELECT count() FROM silver_users" 2>/dev/null | tr -d ' ')"
  echo "  silver_events count: $(CH_Q "SELECT count() FROM silver_events" 2>/dev/null | tr -d ' ')"
  echo "  If silver_events is still 0, check mongo.commerce.events has messages and that the Debezium envelope (after/ts_ms) matches the MV in scripts/clickhouse-init.sql."
fi
