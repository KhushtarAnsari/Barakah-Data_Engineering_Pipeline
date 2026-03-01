-- Part 3: ClickHouse schema - Kafka engine tables and silver layer
-- Run after ClickHouse cluster is up (e.g. kubectl port-forward svc/analytics 8123:8123 -n clickhouse).

-- 1) Raw stream from PostgreSQL CDC (Debezium JSON envelope)
CREATE TABLE IF NOT EXISTS kafka_users_raw
(
    value String
)
ENGINE = Kafka
SETTINGS
    kafka_broker_list = 'data-engineering-kafka-kafka-bootstrap.kafka.svc.cluster.local:9092',
    kafka_topic_list = 'postgres.public.users',
    kafka_group_name = 'clickhouse_users',
    kafka_format = 'JSONAsString',
    kafka_num_consumers = 1;

-- 2) Silver users: current state with soft deletes (ReplacingMergeTree by _version)
CREATE TABLE IF NOT EXISTS silver_users
(
    user_id Int32,
    full_name String,
    email String,
    created_at DateTime64(3),
    updated_at DateTime64(3),
    _version UInt64,
    _deleted UInt8 DEFAULT 0
)
ENGINE = ReplacingMergeTree(_version)
ORDER BY user_id;

-- 3) Materialized view: parse Debezium envelope (op, before, after) -> silver_users
-- op: c=insert, u=update, d=delete. For d we insert a row with _deleted=1 using "before" for key.
CREATE MATERIALIZED VIEW IF NOT EXISTS silver_users_mv TO silver_users AS
SELECT
    toInt32(if(JSONExtractString(value, 'op') = 'd', JSONExtractString(value, 'before', 'user_id'), JSONExtractString(value, 'after', 'user_id'))) AS user_id,
    if(JSONExtractString(value, 'op') = 'd', '', JSONExtractString(value, 'after', 'full_name')) AS full_name,
    if(JSONExtractString(value, 'op') = 'd', '', JSONExtractString(value, 'after', 'email')) AS email,
    parseDateTime64BestEffort(if(JSONExtractString(value, 'op') = 'd', '1970-01-01 00:00:00', JSONExtractString(value, 'after', 'created_at')), 3) AS created_at,
    parseDateTime64BestEffort(if(JSONExtractString(value, 'op') = 'd', '1970-01-01 00:00:00', JSONExtractString(value, 'after', 'updated_at')), 3) AS updated_at,
    toUInt64(JSONExtractUInt(value, 'source', 'ts_ms')) AS _version,
    if(JSONExtractString(value, 'op') = 'd', 1, 0) AS _deleted
FROM kafka_users_raw;

-- 4) Raw stream from MongoDB CDC (Debezium: fullDocument or patch)
CREATE TABLE IF NOT EXISTS kafka_events_raw
(
    value String
)
ENGINE = Kafka
SETTINGS
    kafka_broker_list = 'data-engineering-kafka-kafka-bootstrap.kafka.svc.cluster.local:9092',
    kafka_topic_list = 'mongo.commerce.events',
    kafka_group_name = 'clickhouse_events',
    kafka_format = 'JSONAsString',
    kafka_num_consumers = 1;

-- 5) Silver events: flattened event data from MongoDB
CREATE TABLE IF NOT EXISTS silver_events
(
    event_ts DateTime64(3),
    user_id Int32,
    action String,
    metadata String,
    _source_ts UInt64
)
ENGINE = MergeTree
ORDER BY (user_id, event_ts);

-- 6) MV: parse MongoDB Debezium envelope -> silver_events
-- Debezium MongoDB uses "after" (stringified JSON). timestamp is {"$date": epoch_ms}; extract via nested object.
CREATE MATERIALIZED VIEW IF NOT EXISTS silver_events_mv TO silver_events AS
SELECT
    toDateTime64(JSONExtractUInt(JSONExtractRaw(JSONExtractString(value, 'after'), 'timestamp'), '$date') / 1000, 3) AS event_ts,
    toInt32(JSONExtractInt(JSONExtractString(value, 'after'), 'user_id')) AS user_id,
    JSONExtractString(JSONExtractString(value, 'after'), 'action') AS action,
    JSONExtractRaw(JSONExtractString(value, 'after'), 'metadata') AS metadata,
    toUInt64(JSONExtractUInt(value, 'ts_ms')) AS _source_ts
FROM kafka_events_raw
WHERE JSONExtractString(value, 'after') != '';

-- 7) Gold table: daily user activity (populated by Airflow DAG)
CREATE TABLE IF NOT EXISTS gold_user_activity
(
    activity_date Date,
    user_id Int32,
    total_events UInt64,
    last_event_ts DateTime64(3)
)
ENGINE = ReplacingMergeTree(last_event_ts)
ORDER BY (activity_date, user_id);
