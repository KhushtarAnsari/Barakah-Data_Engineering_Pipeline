-- Reset Kafka consumer groups so ClickHouse reads from earliest (full snapshot).
-- Run when silver_* are empty but Kafka topics have data.
-- Usage: kubectl exec -i -n clickhouse $CH_POD -- clickhouse-client --user=default --password=default --multiquery < scripts/clickhouse-kafka-reset-consumer-groups.sql

-- Users pipeline: drop MV and Kafka table, recreate with new consumer group
DROP VIEW IF EXISTS silver_users_mv;
DROP TABLE IF EXISTS kafka_users_raw;

CREATE TABLE kafka_users_raw
(
    value String
)
ENGINE = Kafka
SETTINGS
    kafka_broker_list = 'data-engineering-kafka-kafka-bootstrap.kafka.svc.cluster.local:9092',
    kafka_topic_list = 'postgres.public.users',
    kafka_group_name = 'clickhouse_users_v3',
    kafka_format = 'JSONAsString',
    kafka_num_consumers = 1;

CREATE MATERIALIZED VIEW silver_users_mv TO silver_users AS
SELECT
    toInt32(if(JSONExtractString(value, 'op') = 'd', JSONExtractString(value, 'before', 'user_id'), JSONExtractString(value, 'after', 'user_id'))) AS user_id,
    if(JSONExtractString(value, 'op') = 'd', '', JSONExtractString(value, 'after', 'full_name')) AS full_name,
    if(JSONExtractString(value, 'op') = 'd', '', JSONExtractString(value, 'after', 'email')) AS email,
    parseDateTime64BestEffort(if(JSONExtractString(value, 'op') = 'd', '1970-01-01 00:00:00', JSONExtractString(value, 'after', 'created_at')), 3) AS created_at,
    parseDateTime64BestEffort(if(JSONExtractString(value, 'op') = 'd', '1970-01-01 00:00:00', JSONExtractString(value, 'after', 'updated_at')), 3) AS updated_at,
    toUInt64(JSONExtractUInt(value, 'source', 'ts_ms')) AS _version,
    if(JSONExtractString(value, 'op') = 'd', 1, 0) AS _deleted
FROM kafka_users_raw;

-- Events pipeline: drop MV and Kafka table, recreate with new consumer group
DROP VIEW IF EXISTS silver_events_mv;
DROP TABLE IF EXISTS kafka_events_raw;

CREATE TABLE kafka_events_raw
(
    value String
)
ENGINE = Kafka
SETTINGS
    kafka_broker_list = 'data-engineering-kafka-kafka-bootstrap.kafka.svc.cluster.local:9092',
    kafka_topic_list = 'mongo.commerce.events',
    kafka_group_name = 'clickhouse_events_v3',
    kafka_format = 'JSONAsString',
    kafka_num_consumers = 1;

-- Debezium MongoDB uses "after" (stringified JSON), timestamp is {"$date": epoch_ms}.
-- Extract timestamp via nested object so "$date" key is parsed reliably.
CREATE MATERIALIZED VIEW silver_events_mv TO silver_events AS
SELECT
    toDateTime64(JSONExtractUInt(JSONExtractRaw(JSONExtractString(value, 'after'), 'timestamp'), '$date') / 1000, 3) AS event_ts,
    toInt32(JSONExtractInt(JSONExtractString(value, 'after'), 'user_id')) AS user_id,
    JSONExtractString(JSONExtractString(value, 'after'), 'action') AS action,
    JSONExtractRaw(JSONExtractString(value, 'after'), 'metadata') AS metadata,
    toUInt64(JSONExtractUInt(value, 'ts_ms')) AS _source_ts
FROM kafka_events_raw
WHERE JSONExtractString(value, 'after') != '';
