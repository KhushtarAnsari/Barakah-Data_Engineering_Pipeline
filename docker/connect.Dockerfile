# Strimzi Kafka Connect base (has /opt/kafka/kafka_connect_run.sh) + Debezium plugins
# Build: ./scripts/build-connect-image.sh
FROM quay.io/strimzi/kafka:0.50.0-kafka-4.1.0
USER root
# Install unzip (UBI minimal: microdnf; fallback for other bases)
RUN (microdnf install -y unzip 2>/dev/null || yum install -y unzip 2>/dev/null || true) && (microdnf clean all 2>/dev/null || true)
RUN mkdir -p /opt/kafka/plugins/debezium-postgres /opt/kafka/plugins/debezium-mongodb && \
    curl -sL -o /tmp/pg.zip https://repo1.maven.org/maven2/io/debezium/debezium-connector-postgres/2.5.2.Final/debezium-connector-postgres-2.5.2.Final-plugin.zip && \
    (unzip -q -o /tmp/pg.zip -d /opt/kafka/plugins/debezium-postgres || (cd /opt/kafka/plugins/debezium-postgres && jar xf /tmp/pg.zip)) && rm -f /tmp/pg.zip && \
    curl -sL -o /tmp/mongo.zip https://repo1.maven.org/maven2/io/debezium/debezium-connector-mongodb/2.5.2.Final/debezium-connector-mongodb-2.5.2.Final-plugin.zip && \
    (unzip -q -o /tmp/mongo.zip -d /opt/kafka/plugins/debezium-mongodb || (cd /opt/kafka/plugins/debezium-mongodb && jar xf /tmp/mongo.zip)) && rm -f /tmp/mongo.zip
USER 1001
