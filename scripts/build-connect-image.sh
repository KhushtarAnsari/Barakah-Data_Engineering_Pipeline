#!/usr/bin/env bash
# Build Strimzi-based Kafka Connect image with Debezium plugins and load into Kind.
# Run once before deploying Kafka Connect (or after changing docker/connect.Dockerfile).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
IMAGE_NAME="${IMAGE_NAME:-debezium-connect:4.1.0}"
KIND_NAME="${CLUSTER_NAME:-data-engineering-challenge}"

echo "Building $IMAGE_NAME from Strimzi base + Debezium plugins..."
docker build -t "$IMAGE_NAME" -f "$REPO_ROOT/docker/connect.Dockerfile" "$REPO_ROOT"

echo "Loading image into Kind cluster $KIND_NAME..."
kind load docker-image "$IMAGE_NAME" --name "$KIND_NAME"

echo "Done. Deploy Kafka Connect with: ./scripts/05-deploy-kafka.sh (or setup-after-kind.sh)"
