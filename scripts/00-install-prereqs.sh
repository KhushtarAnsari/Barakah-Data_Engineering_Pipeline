#!/usr/bin/env bash
# Install prerequisites for the Data Engineering Challenge (macOS with Homebrew).
# Run in your terminal: ./scripts/00-install-prereqs.sh
# If you see "Cellar is not writable", run first: sudo chown -R $(whoami) /usr/local/Cellar /usr/local/var/homebrew

set -euo pipefail

echo "Checking Homebrew..."
if ! command -v brew &>/dev/null; then
    echo "Homebrew not found. Install from https://brew.sh"
    exit 1
fi

echo "Installing kubectl, kind, helm..."
brew install kubectl kind helm

echo "Installing Docker Desktop (required for Kind)..."
brew install --cask docker
echo "Docker Desktop installed. You may need to open the app and accept the terms."

# ClickHouse client is optional (only needed to run ClickHouse init SQL from your machine).
# Skip if deprecated or failing; you can use Option B (exec into pod) in SETUP_STEPS.md instead.
if brew info clickhouse &>/dev/null 2>&1; then
    echo "Installing clickhouse-client (optional)..."
    brew install clickhouse || echo "ClickHouse install skipped (optional). Use Option B in SETUP_STEPS.md for schema init."
else
    echo "ClickHouse formula deprecated/skipped. Use Option B in SETUP_STEPS.md for schema init."
fi

echo ""
echo "Verifying..."
command -v kubectl && kubectl version --client
command -v kind && kind version
command -v helm && helm version --short
command -v docker && docker --version || echo "Docker: start Docker Desktop and run 'docker --version'"

echo ""
echo "Prerequisites install complete. Start Docker Desktop, then run ./scripts/01-create-cluster.sh"
