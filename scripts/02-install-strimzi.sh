#!/usr/bin/env bash
# Install Strimzi Kafka operator (Kraft) in kafka namespace
set -euo pipefail

echo "Installing Strimzi operator..."
kubectl get namespace kafka &>/dev/null || kubectl create namespace kafka
# Use apply so re-runs are idempotent (create would fail with AlreadyExists)
kubectl apply -f 'https://strimzi.io/install/latest?namespace=kafka' -n kafka

echo "Waiting for Strimzi operator to be ready..."
kubectl wait --for=condition=Available deployment/strimzi-cluster-operator -n kafka --timeout=300s
echo "Strimzi operator installed."
