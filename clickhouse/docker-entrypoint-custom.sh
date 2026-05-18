#!/bin/bash
set -e

# Start ClickHouse server in background
/entrypoint.sh &
CLICKHOUSE_PID=$!

echo "Waiting for ClickHouse to be ready..."
for i in {1..60}; do
  if clickhouse-client --host=localhost -u default --password="" -q "SELECT 1" &>/dev/null; then
    echo "ClickHouse is ready!"
    break
  fi
  if [ $i -eq 60 ]; then
    echo "ClickHouse failed to start"
    exit 1
  fi
  sleep 1
done

echo "Recreating SigNoz schema..."

# Single transaction to ensure atomicity
clickhouse-client --host=localhost -u default --password="" <<'SCHEMA_EOF'
-- Create database
CREATE DATABASE IF NOT EXISTS signoz_metrics;
CREATE DATABASE IF NOT EXISTS signoz_traces;
CREATE DATABASE IF NOT EXISTS signoz_logs;

-- Drop and recreate metrics tables (official SigNoz schemas)
DROP TABLE IF EXISTS signoz_metrics.distributed_exemplars_v4;
DROP TABLE IF EXISTS signoz_metrics.distributed_samples_v4;
DROP TABLE IF EXISTS signoz_metrics.distributed_time_series_v4;
DROP TABLE IF EXISTS signoz_metrics.time_series_v4_6hrs;
DROP TABLE IF EXISTS signoz_metrics.time_series_v4_1day;
DROP TABLE IF EXISTS signoz_metrics.exemplars_v4;
DROP TABLE IF EXISTS signoz_metrics.samples_v4;
DROP TABLE IF EXISTS signoz_metrics.time_series_v4;

-- Official SigNoz Samples Table
CREATE TABLE IF NOT EXISTS signoz_metrics.samples_v4
(
    env LowCardinality(String) DEFAULT 'default',
    temporality LowCardinality(String) DEFAULT 'Unspecified',
    metric_name LowCardinality(String),
    fingerprint UInt64 CODEC(Delta(8), ZSTD(1)),
    unix_milli Int64 CODEC(DoubleDelta, ZSTD(1)),
    value Float64 CODEC(Gorilla, ZSTD(1))
)
ENGINE = MergeTree()
ORDER BY (env, temporality, metric_name, fingerprint, unix_milli)
PARTITION BY toDate(fromUnixTimestamp64Milli(unix_milli));

-- Official SigNoz Time Series Table
CREATE TABLE IF NOT EXISTS signoz_metrics.time_series_v4
(
    env LowCardinality(String) DEFAULT 'default',
    temporality LowCardinality(String) DEFAULT 'Unspecified',
    metric_name LowCardinality(String),
    description LowCardinality(String) DEFAULT '' CODEC(ZSTD(1)),
    unit LowCardinality(String) DEFAULT '' CODEC(ZSTD(1)),
    type LowCardinality(String) DEFAULT '' CODEC(ZSTD(1)),
    is_monotonic Bool DEFAULT false CODEC(ZSTD(1)),
    fingerprint UInt64 CODEC(Delta(8), ZSTD(1)),
    unix_milli Int64 CODEC(Delta(8), ZSTD(1)),
    labels String CODEC(ZSTD(5))
)
ENGINE = MergeTree()
ORDER BY (env, temporality, metric_name, fingerprint, unix_milli)
PARTITION BY toDate(fromUnixTimestamp64Milli(unix_milli));

-- Aggregated time series
CREATE TABLE IF NOT EXISTS signoz_metrics.time_series_v4_6hrs AS signoz_metrics.time_series_v4;
CREATE TABLE IF NOT EXISTS signoz_metrics.time_series_v4_1day AS signoz_metrics.time_series_v4;

-- Minimal Exemplars table (keep unix_milli aligned)
CREATE TABLE IF NOT EXISTS signoz_metrics.exemplars_v4 (
    env LowCardinality(String) DEFAULT 'default',
    metric_name LowCardinality(String),
    fingerprint UInt64,
    unix_milli Int64,
    value Float64,
    trace_id String,
    span_id String
) ENGINE = MergeTree()
ORDER BY (env, metric_name, fingerprint, unix_milli)
PARTITION BY toDate(fromUnixTimestamp64Milli(unix_milli));

-- Metadata (official schema expects metadata for metrics)
CREATE TABLE IF NOT EXISTS signoz_metrics.metadata
(
    metric_name LowCardinality(String),
    type LowCardinality(String),
    unit LowCardinality(String),
    description String,
    temporality LowCardinality(String),
    is_monotonic Bool,
    created_at DateTime DEFAULT now()
)
ENGINE = MergeTree()
ORDER BY (metric_name, type);

-- Distributed tables for cluster setup (sharding using cityHash64)
CREATE TABLE IF NOT EXISTS signoz_metrics.distributed_samples_v4 AS signoz_metrics.samples_v4
ENGINE = Distributed('cluster', 'signoz_metrics', 'samples_v4', cityHash64(env, temporality, metric_name, fingerprint));

CREATE TABLE IF NOT EXISTS signoz_metrics.distributed_time_series_v4 AS signoz_metrics.time_series_v4
ENGINE = Distributed('cluster', 'signoz_metrics', 'time_series_v4', cityHash64(env, temporality, metric_name, fingerprint));

CREATE TABLE IF NOT EXISTS signoz_metrics.distributed_exemplars_v4 AS signoz_metrics.exemplars_v4
ENGINE = Distributed('cluster', 'signoz_metrics', 'exemplars_v4', cityHash64(env, metric_name, fingerprint));

CREATE TABLE IF NOT EXISTS signoz_metrics.distributed_metadata AS signoz_metrics.metadata
ENGINE = Distributed('cluster', 'signoz_metrics', 'metadata', cityHash64(metric_name, type));

-- Drop and recreate traces tables
DROP TABLE IF EXISTS signoz_traces.distributed_spans;
DROP TABLE IF EXISTS signoz_traces.span_index;
DROP TABLE IF EXISTS signoz_traces.spans;

CREATE TABLE signoz_traces.spans (
    traceID String,
    spanID String,
    parentSpanID String,
    operationName String,
    serviceName String,
    kind Int8,
    startTime DateTime,
    duration UInt64,
    statusCode Int32,
    statusMessage String,
    attributes String,
    resourceAttributes String,
    events String,
    links String,
    spanContext String,
    instrumentationLibraryName String,
    instrumentationLibraryVersion String
) ENGINE = MergeTree()
ORDER BY (serviceName, startTime)
TTL startTime + INTERVAL 72 HOUR;

CREATE TABLE signoz_traces.distributed_spans AS signoz_traces.spans
ENGINE = Distributed('cluster', 'signoz_traces', 'spans', rand());

CREATE TABLE signoz_traces.span_index (
    traceID String,
    spanID String,
    startTime DateTime,
    serviceName String,
    operationName String
) ENGINE = MergeTree()
ORDER BY (traceID, startTime)
TTL startTime + INTERVAL 72 HOUR;

-- Drop and recreate logs tables
DROP TABLE IF EXISTS signoz_logs.distributed_logs;
DROP TABLE IF EXISTS signoz_logs.logs_index;
DROP TABLE IF EXISTS signoz_logs.logs;

CREATE TABLE signoz_logs.logs (
    timestamp DateTime,
    severity_text String,
    severity_number UInt32,
    body String,
    resource_attributes String,
    resource_name String,
    service_name String,
    attributes String,
    trace_id String,
    span_id String,
    trace_flags UInt32
) ENGINE = MergeTree()
ORDER BY (service_name, timestamp)
TTL timestamp + INTERVAL 7 DAY;

CREATE TABLE signoz_logs.distributed_logs AS signoz_logs.logs
ENGINE = Distributed('cluster', 'signoz_logs', 'logs', rand());

CREATE TABLE signoz_logs.logs_index (
    timestamp DateTime,
    service_name String,
    severity_text String,
    body String
) ENGINE = MergeTree()
ORDER BY (service_name, timestamp, severity_text)
TTL timestamp + INTERVAL 7 DAY;

SCHEMA_EOF

if [ $? -eq 0 ]; then
  echo "Schema recreation completed successfully!"
else
  echo "Schema recreation failed, but continuing..."
fi

# Keep ClickHouse running
wait $CLICKHOUSE_PID
