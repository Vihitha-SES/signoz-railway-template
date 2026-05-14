-- Metrics Tables for SigNoz v0.144.2

-- Time series table (local)
CREATE TABLE IF NOT EXISTS signoz_metrics.time_series_v4 (
    env String,
    temporality String,
    metric_name String,
    description String,
    unit String,
    type String,
    is_monotonic Boolean,
    fingerprint UInt64,
    unix_milli Int64,
    labels String,
    attrs String,
    scope_attrs String,
    resource_attrs String,
    __normalized String DEFAULT '',
    inserted_at_unix_milli Int64 DEFAULT toUnixTimestamp(now()) * 1000
) ENGINE = MergeTree()
ORDER BY (env, metric_name, fingerprint, unix_milli)
TTL toDateTime(inserted_at_unix_milli / 1000) + INTERVAL 7 DAY
SETTINGS index_granularity = 8192;

-- Time series distributed table
CREATE TABLE IF NOT EXISTS signoz_metrics.distributed_time_series_v4 AS signoz_metrics.time_series_v4
ENGINE = Distributed('cluster', 'signoz_metrics', 'time_series_v4', rand());

-- Samples table (local) - for storing individual metric samples
CREATE TABLE IF NOT EXISTS signoz_metrics.samples_v4 (
    env String,
    temporality String,
    metric_name String,
    fingerprint UInt64,
    unix_milli Int64,
    value Float64,
    flags UInt32,
    inserted_at_unix_milli Int64 DEFAULT toUnixTimestamp(now()) * 1000
) ENGINE = MergeTree()
ORDER BY (env, metric_name, fingerprint, unix_milli)
TTL toDateTime(inserted_at_unix_milli / 1000) + INTERVAL 7 DAY
SETTINGS index_granularity = 8192;

-- Samples distributed table
CREATE TABLE IF NOT EXISTS signoz_metrics.distributed_samples_v4 AS signoz_metrics.samples_v4
ENGINE = Distributed('cluster', 'signoz_metrics', 'samples_v4', rand());

-- Exemplars table (local)
CREATE TABLE IF NOT EXISTS signoz_metrics.exemplars_v4 (
    env String,
    metric_name String,
    fingerprint UInt64,
    unix_milli Int64,
    value Float64,
    trace_id String,
    span_id String,
    inserted_at_unix_milli Int64 DEFAULT toUnixTimestamp(now()) * 1000
) ENGINE = MergeTree()
ORDER BY (env, metric_name, fingerprint, unix_milli)
TTL toDateTime(inserted_at_unix_milli / 1000) + INTERVAL 7 DAY
SETTINGS index_granularity = 8192;

-- Exemplars distributed table
CREATE TABLE IF NOT EXISTS signoz_metrics.distributed_exemplars_v4 AS signoz_metrics.exemplars_v4
ENGINE = Distributed('cluster', 'signoz_metrics', 'exemplars_v4', rand());
