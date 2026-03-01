#!/usr/bin/env bash
# Part 1: Create Kind cluster for data-engineering-challenge
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-data-engineering-challenge}"

echo "Creating Kind cluster: $CLUSTER_NAME"
kind create cluster --name "$CLUSTER_NAME" --wait 2m

echo "Cluster created. Waiting for node to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=120s

echo "Kind cluster $CLUSTER_NAME is ready."
