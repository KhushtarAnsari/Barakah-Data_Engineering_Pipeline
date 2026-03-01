# Data Engineering Technical Challenge

A local pipeline on **Kind** that streams data from **PostgreSQL** and **MongoDB** into **Kafka** via **Debezium**, then into **ClickHouse** for analytics. A daily **Airflow** DAG aggregates silver data into a gold table.

## Architecture

- **Kind** – local Kubernetes cluster
- **PostgreSQL** – `public.users`; logical replication for CDC
- **MongoDB** – `commerce.events`; replica set for change streams
- **Kafka (Strimzi)** – brokers + Kafka Connect with Debezium
- **ClickHouse (Altinity operator)** – Kafka engine tables + materialized views → `silver_users`, `silver_events`; `gold_user_activity` filled by Airflow
- **Airflow** – one DAG: delete then insert into `gold_user_activity` by date (idempotent, backfill-safe)

## Prerequisites

- Docker, kubectl, Kind, Helm 3
- Optional: `clickhouse-client` (for running init SQL from your machine)

For a full step-by-step guide with verification and troubleshooting, see [SETUP_STEPS.md](SETUP_STEPS.md).

Install Kind example (macOS/Linux):

```bash
curl -Lo ./kind "https://kind.sigs.k8s.io/dl/v0.20.0/kind-$(uname)-amd64"
chmod +x ./kind && sudo mv ./kind /usr/local/bin/kind
```

## Quick Start

### 1. Create cluster and install operators

```bash
chmod +x scripts/*.sh
./scripts/01-create-cluster.sh
./scripts/02-install-strimzi.sh
./scripts/03-install-clickhouse-operator.sh
```

### 2. Deploy data sources

```bash
./scripts/04-deploy-data-sources.sh
```

Creates PostgreSQL (users table, publication, sample data) and MongoDB (replica set, `commerce.events` with sample events).

### 3. Deploy Kafka and Debezium

Build the Connect image (Strimzi base + Debezium), load into Kind, then deploy:

```bash
./scripts/build-connect-image.sh
./scripts/05-deploy-kafka.sh
```

The Connect image must be Strimzi-based; the script builds and loads it. Connectors are created for `postgres.public.users` and `mongo.commerce.events`.

### 4. Deploy ClickHouse and apply schema

```bash
./scripts/06-deploy-clickhouse.sh
```

Wait for the pod to be Ready, then apply schema (use `default` / `default` for user/password as set in the CHI):

```bash
CH_POD=$(kubectl get pod -n clickhouse -l clickhouse.altinity.com/chi=analytics -o jsonpath='{.items[0].metadata.name}')
kubectl exec -i -n clickhouse $CH_POD -- clickhouse-client --user=default --password=default --multiquery < scripts/clickhouse-init.sql
```

If `silver_users` or `silver_events` stay at 0 after a minute, run the sync script (recreates Kafka consumer tables with new consumer groups so ClickHouse reads from the start of the topics):

```bash
./scripts/clickhouse-kafka-sync.sh
```

### 5. Deploy Airflow

```bash
./scripts/07-deploy-airflow.sh
```

When the scheduler is up, copy the DAG:

```bash
SCHEDULER_POD=$(kubectl get pod -n airflow -l component=scheduler -o jsonpath='{.items[0].metadata.name}')
kubectl cp airflow/dags/gold_user_activity_dag.py airflow/$SCHEDULER_POD:/opt/airflow/dags/ -n airflow -c scheduler
```

Create the ClickHouse connection in the UI:

1. `kubectl port-forward svc/airflow-api-server 8080:8080 -n airflow`
2. Open http://localhost:8080 (e.g. admin / admin).
3. Admin → Connections → Add:
   - Connection Id: `clickhouse_default`
   - Type: ClickHouse
   - Host: `clickhouse-analytics.clickhouse.svc.cluster.local`
   - Port: `8123`
   - Schema: `default`
   - Login: `default`
   - Password: `default`

Unpause and trigger the DAG `gold_user_activity_daily`. It runs at 01:00 daily and can be backfilled for past dates.

## One-shot setup (cluster already exists)

If the Kind cluster is already created:

```bash
./scripts/setup-after-kind.sh
```

Then apply ClickHouse schema (step 4 above with `--user=default --password=default`), run `./scripts/clickhouse-kafka-sync.sh` if silver tables are empty, and set the Airflow connection + copy DAG as in step 5.

## What’s in the repo

| Path | Description |
|------|-------------|
| `k8s/` | Namespaces, PostgreSQL, MongoDB, Kafka cluster/connect, Debezium connectors, ClickHouse CHI |
| `scripts/` | Cluster create, operator install, deploy scripts, init SQL/JS, `clickhouse-init.sql`, `clickhouse-kafka-sync.sh`, `clickhouse-kafka-reset-consumer-groups.sql` |
| `airflow/dags/` | `gold_user_activity_dag.py` – daily silver → gold |
| `airflow/values.yaml` | Helm values (LocalExecutor, DAG processor, ClickHouse connection env) |

## Design notes

- **PostgreSQL**: Publication `dbz_publication` on `public.users`; Debezium slot `debezium_users`. Silver users use ReplacingMergeTree with `_version`; deletes are soft (`_deleted=1`). Use `FINAL` and `WHERE _deleted=0` for current state.
- **MongoDB**: Debezium emits an envelope with `after` (the document as a stringified JSON), `op`, `ts_ms`. The silver_events MV parses `after` and extracts `user_id`, `action`, `timestamp.$date`, `metadata`. Deletes in MongoDB are not propagated to ClickHouse (the MV only inserts when `after` is present).
- **Gold DAG**: For the logical date `ds`, deletes existing rows for that date in `gold_user_activity`, then inserts one row per user per day from `silver_events` joined with active `silver_users`.

## Troubleshooting

- **Silver tables empty**: Kafka consumption is background; if topics had data before the consumer started, run `./scripts/clickhouse-kafka-sync.sh` to reset consumer groups and re-read from earliest.
- **Airflow DAGs not listed**: In Airflow 3 the DAG processor must be running (`dagProcessor.enabled: true` in values). After copying the DAG file, wait a minute; copy the DAG again if needed and check scheduler or dag-processor logs for import errors.
- **ClickHouse auth**: The CHI sets `default/password: "default"`. All `clickhouse-client` and DAG calls use `--user=default --password=default`. If you changed the password, update the Airflow connection and the DAG’s `CH_PASSWORD`.
- **Kafka broker pod name**: Scripts use a broker pod matching `data-engineering-kafka-pool-a-0` or similar; if your Strimzi cluster uses a different name, adjust `clickhouse-kafka-sync.sh` and reset SQL broker list if needed.
- **Kind storage**: If PVCs stay Pending, ensure a default StorageClass exists.

## Repository contents (deliverables)

- YAML for Kind: namespaces, PostgreSQL, MongoDB, Kafka (Strimzi), Kafka Connect, Debezium connectors, ClickHouse CHI
- Scripts: cluster create, operator install, deploy, init SQL/JS, ClickHouse schema and Kafka sync
- Airflow: one DAG (`gold_user_activity_daily`) and Helm values
- README with setup and run instructions

## License

MIT
