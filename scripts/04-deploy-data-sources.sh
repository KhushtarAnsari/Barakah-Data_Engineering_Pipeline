#!/usr/bin/env bash
# Deploy PostgreSQL and MongoDB to data-sources namespace
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

kubectl apply -f "$REPO_ROOT/k8s/00-namespaces.yaml"
kubectl apply -f "$REPO_ROOT/k8s/postgres/postgres-configmap.yaml"
kubectl apply -f "$REPO_ROOT/k8s/postgres/postgres-pvc.yaml"
kubectl apply -f "$REPO_ROOT/k8s/postgres/postgres-deployment.yaml"
kubectl apply -f "$REPO_ROOT/k8s/mongodb/mongodb-deployment.yaml"

echo "Waiting for PostgreSQL..."
kubectl wait --for=condition=Available deployment/postgres -n data-sources --timeout=180s || {
  echo "PostgreSQL did not become ready. Check: kubectl get pods -n data-sources; kubectl describe pod -l app=postgres -n data-sources"
  exit 1
}
echo "Waiting for MongoDB..."
kubectl wait --for=condition=Available deployment/mongodb -n data-sources --timeout=180s || {
  echo "MongoDB did not become ready. Check: kubectl get pods -n data-sources; kubectl describe pod -l app=mongodb -n data-sources"
  exit 1
}

echo "Initializing MongoDB replica set (required for Debezium)..."
kubectl apply -f "$REPO_ROOT/k8s/mongodb/mongodb-replicaset-init.yaml"
kubectl wait --for=condition=complete job/mongodb-replicaset-init -n data-sources --timeout=60s || true
sleep 5

echo "Initializing PostgreSQL (users table + publication)..."
kubectl exec -n data-sources deploy/postgres -- psql -U postgres -f - < "$REPO_ROOT/scripts/postgres-init.sql" || true

echo "Initializing MongoDB events collection..."
kubectl cp "$REPO_ROOT/scripts/mongodb-init-events.js" data-sources/$(kubectl get pod -n data-sources -l app=mongodb -o jsonpath='{.items[0].metadata.name}'):/tmp/init.js
kubectl exec -n data-sources deploy/mongodb -- mongosh commerce /tmp/init.js || true

echo "Data sources deployed and initialized."
