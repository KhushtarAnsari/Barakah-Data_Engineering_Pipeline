#!/usr/bin/env bash
# Install Altinity ClickHouse operator
set -euo pipefail

echo "Installing Altinity ClickHouse operator..."
kubectl get namespace clickhouse &>/dev/null || kubectl create namespace clickhouse
kubectl apply -f https://raw.githubusercontent.com/Altinity/clickhouse-operator/master/deploy/operator/clickhouse-operator-install-bundle.yaml

echo "Waiting for ClickHouse operator to be ready..."
kubectl wait --for=condition=Available deployment/clickhouse-operator -n kube-system --timeout=300s 2>/dev/null || \
kubectl wait --for=condition=Available deployment/clickhouse-operator -n default --timeout=300s 2>/dev/null || true
echo "ClickHouse operator installed."
