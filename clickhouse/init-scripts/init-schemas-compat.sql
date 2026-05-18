-- One-shot compatible SigNoz ClickHouse schema migration
-- Run with: clickhouse-client --host <HOST> --user <USER> --password <PASS> < init-schemas-compat.sql

-- Create databases
CREATE DATABASE IF NOT EXISTS signoz_metrics;
CREATE DATABASE IF NOT EXISTS signoz_traces;
CREATE DATABASE IF NOT EXISTS signoz_logs;

-- Samples table
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
PARTITION BY toDate(fromUnixTimestamp64Milli(unix_milli))
SETTINGS index_granularity = 8192;

-- Time series table
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
PARTITION BY toDate(fromUnixTimestamp64Milli(unix_milli))
SETTINGS index_granularity = 8192;

-- Aggregated time series
CREATE TABLE IF NOT EXISTS signoz_metrics.time_series_v4_6hrs AS signoz_metrics.time_series_v4;
CREATE TABLE IF NOT EXISTS signoz_metrics.time_series_v4_1day AS signoz_metrics.time_series_v4;

-- Exemplars
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
PARTITION BY toDate(fromUnixTimestamp64Milli(unix_milli))
SETTINGS index_granularity = 8192;

-- Metadata
CREATE TABLE IF NOT EXISTS signoz_metrics.metadata (
    metric_name LowCardinality(String),
    type LowCardinality(String),
    unit LowCardinality(String),
    description String,
    temporality LowCardinality(String),
    is_monotonic Bool,
    created_at DateTime DEFAULT now()
) ENGINE = MergeTree()
ORDER BY (metric_name, type);

-- Distributed wrappers
CREATE TABLE IF NOT EXISTS signoz_metrics.distributed_samples_v4 AS signoz_metrics.samples_v4
ENGINE = Distributed('cluster', 'signoz_metrics', 'samples_v4', cityHash64(env, temporality, metric_name, fingerprint));

CREATE TABLE IF NOT EXISTS signoz_metrics.distributed_time_series_v4 AS signoz_metrics.time_series_v4
ENGINE = Distributed('cluster', 'signoz_metrics', 'time_series_v4', cityHash64(env, temporality, metric_name, fingerprint));

CREATE TABLE IF NOT EXISTS signoz_metrics.distributed_time_series_v4_6hrs AS signoz_metrics.time_series_v4_6hrs
ENGINE = Distributed('cluster', 'signoz_metrics', 'time_series_v4_6hrs', cityHash64(env, temporality, metric_name, fingerprint));

CREATE TABLE IF NOT EXISTS signoz_metrics.distributed_time_series_v4_1day AS signoz_metrics.time_series_v4_1day
ENGINE = Distributed('cluster', 'signoz_metrics', 'time_series_v4_1day', cityHash64(env, temporality, metric_name, fingerprint));

CREATE TABLE IF NOT EXISTS signoz_metrics.distributed_exemplars_v4 AS signoz_metrics.exemplars_v4
ENGINE = Distributed('cluster', 'signoz_metrics', 'exemplars_v4', cityHash64(env, metric_name, fingerprint));

CREATE TABLE IF NOT EXISTS signoz_metrics.distributed_metadata AS signoz_metrics.metadata
ENGINE = Distributed('cluster', 'signoz_metrics', 'metadata', cityHash64(metric_name, type));

-- Traces and logs minimal
CREATE TABLE IF NOT EXISTS signoz_traces.spans (
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

CREATE TABLE IF NOT EXISTS signoz_logs.logs (
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
