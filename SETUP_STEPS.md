# Setup Steps – Data Engineering Challenge

Follow these steps in order. All commands assume you are in the repository root.

---

## Phase 0: Prerequisites

**Option A – Install everything with one script (macOS with Homebrew):**
```bash
cd /path/to/KA_Barakah_Test
chmod +x scripts/*.sh
./scripts/00-install-prereqs.sh
```
If you see "Cellar is not writable", fix Homebrew permissions first:
```bash
sudo chown -R $(whoami) /usr/local/Cellar /usr/local/var/homebrew
```
Then open **Docker Desktop** from Applications and complete setup. Continue at Phase 1.

**Option B – Install each tool manually (below):**

### 0.1 Install Docker
- **macOS**: [Docker Desktop](https://docs.docker.com/desktop/install/mac-install/) or `brew install --cask docker`
- **Linux**: `curl -fsSL https://get.docker.com | sh` then `sudo usermod -aG docker $USER` (log out and back in)
- Verify: `docker run hello-world`

### 0.2 Install kubectl
- **macOS**: `brew install kubectl`
- **Linux**: `curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && chmod +x kubectl && sudo mv kubectl /usr/local/bin/`
- Verify: `kubectl version --client`

### 0.3 Install Kind
```bash
# macOS (Intel/Apple Silicon)
curl -Lo ./kind "https://kind.sigs.k8s.io/dl/v0.20.0/kind-$(uname)-amd64"
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind

# Or with Homebrew
brew install kind
```
- Verify: `kind version`

### 0.4 Install Helm 3
```bash
# macOS
brew install helm

# Linux
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```
- Verify: `helm version`

### 0.5 (Optional) Install clickhouse-client
- **macOS**: `brew install clickhouse`
- **Linux**: See [ClickHouse install](https://clickhouse.com/docs/en/install)
- Only needed if you run ClickHouse init SQL from your machine (Option A in Phase 3).

### 0.6 Clone or unpack the repo
```bash
cd /path/to/KA_Barakah_Test
# Ensure scripts are executable
chmod +x scripts/*.sh
```

---

## Phase 1: Kind cluster and operators

### 1.1 Create the Kind cluster
```bash
./scripts/01-create-cluster.sh
```
- Creates cluster named `data-engineering-challenge`.
- Verify: `kubectl cluster-info --context kind-data-engineering-challenge` and `kubectl get nodes`.

### 1.2 Install Strimzi (Kafka) operator
```bash
./scripts/02-install-strimzi.sh
```
- Installs Strimzi in namespace `kafka`.
- Verify: `kubectl get pods -n kafka -l name=strimzi-cluster-operator` (Running).

### 1.3 Install Altinity ClickHouse operator
```bash
./scripts/03-install-clickhouse-operator.sh
```
- Installs operator (often in `kube-system`).
- Verify: `kubectl get pods -n kube-system -l app.kubernetes.io/name=clickhouse-operator` (or in `default`).

### 1.4 Ensure default StorageClass (for PVCs)
```bash
kubectl get storageclass
```
- If none is marked `(default)`, create one or patch an existing one. Many Kind setups use `kindnet` or a custom provisioner; see [Kind storage](https://kind.sigs.k8s.io/docs/user/local-storage/).

---

## Phase 2: Data sources (PostgreSQL and MongoDB)

### 2.1 Deploy namespaces and data sources
```bash
./scripts/04-deploy-data-sources.sh
```
This script:
- Applies `k8s/00-namespaces.yaml`
- Deploys PostgreSQL (ConfigMap with `wal_level=logical`, PVC, Deployment, Service)
- Deploys MongoDB (PVC, Deployment with `--replSet rs0`, Service)
- Waits for both deployments
- Runs MongoDB replica set init Job
- Runs PostgreSQL init SQL (users table, publication, sample data, updates, deletes)
- Runs MongoDB init JS (commerce.events with sample events)

### 2.2 Verify PostgreSQL
```bash
kubectl get pods -n data-sources -l app=postgres
kubectl exec -n data-sources deploy/postgres -- psql -U postgres -c "\dt public.*"
kubectl exec -n data-sources deploy/postgres -- psql -U postgres -c "SELECT * FROM public.users;"
kubectl exec -n data-sources deploy/postgres -- psql -U postgres -c "\dRp+"
```
- You should see table `users` and publication `dbz_publication`.

### 2.3 Verify MongoDB
```bash
kubectl get pods -n data-sources -l app=mongodb
kubectl exec -n data-sources deploy/mongodb -- mongosh --eval "rs.status().ok"
kubectl exec -n data-sources deploy/mongodb -- mongosh commerce --eval "db.events.countDocuments()"
```
- Replica set should be 1 and events count > 0.

### 2.4 If PostgreSQL or MongoDB init failed
- **PostgreSQL**: Run init manually:
  ```bash
  kubectl exec -i -n data-sources deploy/postgres -c postgres -- psql -U postgres < scripts/postgres-init.sql
  ```
- **MongoDB replica set**: Run init Job again:
  ```bash
  kubectl delete job mongodb-replicaset-init -n data-sources --ignore-not-found
  kubectl apply -f k8s/mongodb/mongodb-replicaset-init.yaml
  kubectl wait --for=condition=complete job/mongodb-replicaset-init -n data-sources --timeout=60s
  ```
- **MongoDB events**: Copy and run the script:
  ```bash
  POD=$(kubectl get pod -n data-sources -l app=mongodb -o jsonpath='{.items[0].metadata.name}')
  kubectl cp scripts/mongodb-init-events.js data-sources/$POD:/tmp/init.js
  kubectl exec -n data-sources deploy/mongodb -- mongosh commerce /tmp/init.js
  ```

---

## Phase 3: Kafka and Debezium (CDC)

### 3.1 Deploy Kafka cluster
```bash
kubectl apply -f k8s/kafka/kafka-cluster.yaml
kubectl wait --for=condition=Ready kafka/data-engineering-kafka -n kafka --timeout=300s
```
- Verify: `kubectl get kafka -n kafka` and `kubectl get pods -n kafka`.

### 3.2 Deploy Kafka Connect with Debezium
```bash
kubectl apply -f k8s/kafka/kafka-connect.yaml
kubectl wait --for=condition=Ready kafkaconnect/debezium-connect -n kafka --timeout=300s
```
- Verify: `kubectl get kafkaconnect -n kafka` and Connect pod Running.

### 3.3 Create Debezium connectors
```bash
sleep 10
kubectl apply -f k8s/kafka/connector-postgres.yaml
kubectl apply -f k8s/kafka/connector-mongodb.yaml
```

### 3.4 Verify connectors and topics
```bash
kubectl get kafkaconnector -n kafka
# Optional: list topics (use Kafka broker from cluster)
kubectl exec -n kafka data-engineering-kafka-kafka-0 -- bin/kafka-topics.sh --bootstrap-server localhost:9092 --list
```
- You should see topics like `postgres.public.users` and `mongo.commerce.events` (after connector snapshot).

---

## Phase 4: ClickHouse

### 4.1 Deploy ClickHouse (CHI)
```bash
./scripts/06-deploy-clickhouse.sh
# Wait for pod to be Ready (script may not wait long enough)
kubectl wait --for=condition=Ready pod -l clickhouse.altinity.com/chi=analytics -n clickhouse --timeout=300s
```
- If the label differs, list pods: `kubectl get pods -n clickhouse` and wait until the analytics pod is Running.

### 4.2 Get ClickHouse service name
```bash
kubectl get svc -n clickhouse
```
- Note the service you will use for HTTP/client (e.g. `clickhouse-analytics`). Use this for Airflow connection and for port-forward.

### 4.3 Apply ClickHouse schema (Kafka engines, silver, gold)
Choose one:

**Option A – From your machine (with clickhouse-client and port-forward):**
```bash
kubectl port-forward svc/clickhouse-analytics 8123:8123 -n clickhouse &
sleep 2
clickhouse-client --host localhost --user=default --password=default --multiquery < scripts/clickhouse-init.sql
kill %1 2>/dev/null || true
```

**Option B – From inside the cluster (no local clickhouse-client):**
```bash
CH_POD=$(kubectl get pod -n clickhouse -l clickhouse.altinity.com/chi=analytics -o jsonpath='{.items[0].metadata.name}')
kubectl exec -i -n clickhouse $CH_POD -- clickhouse-client --user=default --password=default --multiquery < scripts/clickhouse-init.sql
```

If after a minute `silver_users` or `silver_events` are still empty, run:
```bash
./scripts/clickhouse-kafka-sync.sh
```
This recreates the Kafka engine tables with new consumer groups so consumption starts from the beginning of the topics.

### 4.4 Verify ClickHouse tables
```bash
CH_POD=$(kubectl get pod -n clickhouse -l clickhouse.altinity.com/chi=analytics -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n clickhouse $CH_POD -- clickhouse-client --user=default --password=default -q "SHOW TABLES"
kubectl exec -n clickhouse $CH_POD -- clickhouse-client --user=default --password=default -q "SELECT count() FROM silver_users"
kubectl exec -n clickhouse $CH_POD -- clickhouse-client --user=default --password=default -q "SELECT * FROM silver_users FINAL WHERE _deleted=0"
```
- After CDC has flowed, `silver_users` and `silver_events` should have data. If they stay at 0, run `./scripts/clickhouse-kafka-sync.sh`.

---

## Phase 5: Airflow

### 5.1 Add Helm repo and install Airflow
```bash
helm repo add apache-airflow https://airflow.apache.org
helm repo update
helm upgrade --install airflow apache-airflow/airflow \
  --namespace airflow \
  --create-namespace \
  -f airflow/values.yaml \
  --wait \
  --timeout 10m
```
- Or run: `./scripts/07-deploy-airflow.sh`

### 5.2 Wait for Airflow components
```bash
kubectl get pods -n airflow
```
- Wait until scheduler and api-server (and workers if LocalExecutor) are Running.

### 5.3 Copy the DAG into the scheduler
```bash
SCHEDULER_POD=$(kubectl get pod -n airflow -l component=scheduler -o jsonpath='{.items[0].metadata.name}')
kubectl cp airflow/dags/gold_user_activity_dag.py airflow/$SCHEDULER_POD:/opt/airflow/dags/ -n airflow -c scheduler
```

### 5.4 Create ClickHouse connection in Airflow
1. Port-forward the API server (Airflow 3 uses api-server for UI):
   ```bash
   kubectl port-forward svc/airflow-api-server 8080:8080 -n airflow
   ```
2. Open http://localhost:8080 (default login often `admin` / `admin` – check chart notes).
3. Go to **Admin → Connections**.
4. Add new connection:
   - **Connection Id**: `clickhouse_default`
   - **Connection Type**: **ClickHouse**
   - **Host**: `clickhouse-analytics.clickhouse.svc.cluster.local` (from step 4.2)
   - **Port**: `8123`
   - **Schema**: `default`
   - **Login**: `default`
   - **Password**: `default` (matches CHI config in `k8s/clickhouse/clickhouse-installation.yaml`)
5. Save.

### 5.5 Trigger or backfill the DAG
1. In Airflow UI, open DAG **gold_user_activity_daily**.
2. Unpause it (toggle).
3. **Trigger DAG** (run once) or **Backfill** for a date range (e.g. previous day).
4. Check task logs for `delete_existing_for_date` and `insert_aggregated_activity`.

### 5.6 Verify gold table in ClickHouse
```bash
CH_POD=$(kubectl get pod -n clickhouse -l clickhouse.altinity.com/chi=analytics -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n clickhouse $CH_POD -- clickhouse-client --user=default --password=default -q "SELECT * FROM gold_user_activity ORDER BY activity_date, user_id"
```

### 5.7 Troubleshooting: DAGs not listed
In Airflow 3 the **DAG processor** must be running to parse DAG files and sync them to the DB; the scheduler alone does not parse. If `airflow dags list` shows "No data found":

1. Ensure the DAG processor is deployed (values have `dagProcessor.enabled: true`). Upgrade if needed:
   ```bash
   helm upgrade --install airflow apache-airflow/airflow -n airflow -f airflow/values.yaml --timeout 20m
   ```
2. Wait for the DAG processor pod (and scheduler) to be Running: `kubectl get pods -n airflow`
3. Copy the DAG into the scheduler (see 5.3).
4. Copy the DAG again if needed; then check DAG processor logs for import errors:
   ```bash
   kubectl logs -n airflow -l component=dag-processor -f --tail=100
   ```

---

## Phase 6: End-to-end checks

### 6.1 PostgreSQL → Kafka → ClickHouse (users)
- Change in PostgreSQL:
  ```bash
  kubectl exec -n data-sources deploy/postgres -- psql -U postgres -c "INSERT INTO public.users (full_name, email) VALUES ('Test User', 'test@example.com');"
  ```
- After a short delay, check ClickHouse:
  ```bash
  kubectl exec -n clickhouse $CH_POD -- clickhouse-client --user=default --password=default -q "SELECT * FROM silver_users FINAL WHERE _deleted=0 ORDER BY user_id"
  ```

### 6.2 MongoDB → Kafka → ClickHouse (events)
- Insert in MongoDB:
  ```bash
  kubectl exec -n data-sources deploy/mongodb -- mongosh commerce --eval 'db.events.insertOne({user_id: 1, action: "test_event", timestamp: new Date()})'
  ```
- Check ClickHouse:
  ```bash
  kubectl exec -n clickhouse $CH_POD -- clickhouse-client --user=default --password=default -q "SELECT * FROM silver_events ORDER BY event_ts DESC LIMIT 5"
  ```

### 6.3 Idempotency of the gold DAG
- Trigger the same logical date twice (e.g. yesterday). After the second run, `gold_user_activity` should still have one row per (activity_date, user_id) for that date (no duplicated rows).

---

## One-shot script (optional)

**Kind cluster already created?** Run one script for everything after 1.1 (operators, data sources, Kafka, ClickHouse, schema, Airflow, DAG copy). Then create `clickhouse_default` in Airflow UI (script prints the steps).
```bash
./scripts/setup-after-kind.sh
```

**From scratch** (cluster + all):
```bash
./scripts/setup-all.sh
```
Then: apply ClickHouse schema (Phase 4.3, with `--user=default --password=default`), run `./scripts/clickhouse-kafka-sync.sh` if silver is empty, copy DAG and set ClickHouse connection (Phase 5.3–5.5), then trigger or backfill the DAG.

---

## Cleanup

```bash
kind delete cluster --name data-engineering-challenge
```

---

## Summary checklist

- [ ] Prerequisites: Docker, kubectl, Kind, Helm (and optionally clickhouse-client).
- [ ] Kind cluster created; Strimzi and Altinity operators installed.
- [ ] PostgreSQL and MongoDB deployed; replica set and init scripts run; users and events data present.
- [ ] Kafka cluster and Kafka Connect (Debezium) deployed; PostgreSQL and MongoDB connectors created and running.
- [ ] ClickHouse CHI deployed; `clickhouse-init.sql` applied; silver/gold tables exist.
- [ ] Airflow installed; DAG copied; `clickhouse_default` connection set; DAG triggered or backfilled.
- [ ] Gold table `gold_user_activity` populated and idempotent re-runs verified.
