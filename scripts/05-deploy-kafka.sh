#!/usr/bin/env bash
# Deploy Kafka cluster and Kafka Connect with Debezium
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# If re-running after a timeout, delete the old Kafka first: kubectl delete kafka data-engineering-kafka -n kafka --ignore-not-found
kubectl apply -f "$REPO_ROOT/k8s/kafka/kafka-cluster.yaml"
kubectl apply -f "$REPO_ROOT/k8s/kafka/kafka-node-pool.yaml"
echo "Waiting for Kafka to be ready (up to 5 min)..."
kubectl wait --for=condition=Ready kafka/data-engineering-kafka -n kafka --timeout=300s || {
  echo "Kafka did not become ready. Diagnostics:"
  kubectl get pods -n kafka
  kubectl describe kafka data-engineering-kafka -n kafka | tail -30
  exit 1
}

kubectl apply -f "$REPO_ROOT/k8s/kafka/kafka-connect.yaml"
echo "Waiting for Kafka Connect to be ready (up to 10 min; image pull and JVM startup can be slow)..."
kubectl wait --for=condition=Ready kafkaconnect/debezium-connect -n kafka --timeout=600s || {
  echo "Kafka Connect did not become ready. Diagnostics:"
  kubectl get pods -n kafka
  kubectl describe kafkaconnect debezium-connect -n kafka | tail -40
  echo "Pod logs (if CrashLoopBackOff): kubectl logs -n kafka -l strimzi.io/cluster=debezium-connect --tail=80"
  exit 1
}

# Connectors after Connect is up
sleep 10
kubectl apply -f "$REPO_ROOT/k8s/kafka/connector-postgres.yaml"
kubectl apply -f "$REPO_ROOT/k8s/kafka/connector-mongodb.yaml"

echo "Kafka and Debezium Connect deployed. Connectors created."
