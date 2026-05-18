-- Metrics Tables for SigNoz v0.144.2
-- Drop existing broken tables first
DROP TABLE IF EXISTS signoz_metrics.distributed_exemplars_v4;
DROP TABLE IF EXISTS signoz_metrics.distributed_samples_v4;
DROP TABLE IF EXISTS signoz_metrics.distributed_time_series_v4;
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
PARTITION BY toDate(fromUnixTimestamp64Milli(unix_milli))
SETTINGS index_granularity = 8192;

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
PARTITION BY toDate(fromUnixTimestamp64Milli(unix_milli))
SETTINGS index_granularity = 8192;

-- Aggregated time series
CREATE TABLE IF NOT EXISTS signoz_metrics.time_series_v4_6hrs AS signoz_metrics.time_series_v4;
CREATE TABLE IF NOT EXISTS signoz_metrics.time_series_v4_1day AS signoz_metrics.time_series_v4;

-- Exemplars table (local)
CREATE TABLE IF NOT EXISTS signoz_metrics.exemplars_v4 (
    env LowCardinality(String) DEFAULT 'default',
    metric_name LowCardinality(String),
    fingerprint UInt64,
    unix_milli Int64,
) ENGINE = MergeTree()
ORDER BY (env, metric_name, fingerprint, unix_milli)
PARTITION BY toDate(fromUnixTimestamp64Milli(unix_milli))
SETTINGS index_granularity = 8192;

-- Distributed wrappers for aggregated time series
CREATE TABLE IF NOT EXISTS signoz_metrics.distributed_time_series_v4_6hrs AS signoz_metrics.time_series_v4_6hrs
ENGINE = Distributed('cluster', 'signoz_metrics', 'time_series_v4_6hrs', cityHash64(env, temporality, metric_name, fingerprint));

CREATE TABLE IF NOT EXISTS signoz_metrics.distributed_time_series_v4_1day AS signoz_metrics.time_series_v4_1day
ENGINE = Distributed('cluster', 'signoz_metrics', 'time_series_v4_1day', cityHash64(env, temporality, metric_name, fingerprint));
) ENGINE = MergeTree()
ORDER BY (env, metric_name, fingerprint, unix_milli)
PARTITION BY toDate(fromUnixTimestamp64Milli(unix_milli))
SETTINGS index_granularity = 8192;

-- Metadata table (official schema)
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

-- Distributed tables for cluster setup
CREATE TABLE IF NOT EXISTS signoz_metrics.distributed_samples_v4 AS signoz_metrics.samples_v4
ENGINE = Distributed('cluster', 'signoz_metrics', 'samples_v4', cityHash64(env, temporality, metric_name, fingerprint));

CREATE TABLE IF NOT EXISTS signoz_metrics.distributed_time_series_v4 AS signoz_metrics.time_series_v4
ENGINE = Distributed('cluster', 'signoz_metrics', 'time_series_v4', cityHash64(env, temporality, metric_name, fingerprint));

CREATE TABLE IF NOT EXISTS signoz_metrics.distributed_exemplars_v4 AS signoz_metrics.exemplars_v4
ENGINE = Distributed('cluster', 'signoz_metrics', 'exemplars_v4', cityHash64(env, metric_name, fingerprint));

CREATE TABLE IF NOT EXISTS signoz_metrics.distributed_metadata AS signoz_metrics.metadata
ENGINE = Distributed('cluster', 'signoz_metrics', 'metadata', cityHash64(metric_name, type));
