-- Metrics Tables for SigNoz v0.144.2

-- Time series table for metrics (6 hour TTL)
CREATE TABLE IF NOT EXISTS signoz_metrics.time_series_v4_6hrs (
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
    inserted_at_unix_milli Int64 DEFAULT toUnixTimestamp(now()) * 1000,
    timestamp_ms Int64
) ENGINE = MergeTree()
ORDER BY (env, metric_name, fingerprint, unix_milli)
TTL toDateTime(inserted_at_unix_milli / 1000) + INTERVAL 6 HOUR
SETTINGS index_granularity = 8192;

-- Distributed metrics table
CREATE TABLE IF NOT EXISTS signoz_metrics.distributed_metrics_v4_6hrs AS signoz_metrics.time_series_v4_6hrs
ENGINE = Distributed('cluster', 'signoz_metrics', 'time_series_v4_6hrs', rand());

-- Metrics table with longer retention (7 days)
CREATE TABLE IF NOT EXISTS signoz_metrics.time_series_v4_7d (
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
    inserted_at_unix_milli Int64 DEFAULT toUnixTimestamp(now()) * 1000,
    timestamp_ms Int64
) ENGINE = MergeTree()
ORDER BY (env, metric_name, fingerprint, unix_milli)
TTL toDateTime(inserted_at_unix_milli / 1000) + INTERVAL 7 DAY
SETTINGS index_granularity = 8192;

-- Distributed metrics table for 7d
CREATE TABLE IF NOT EXISTS signoz_metrics.distributed_metrics_v4_7d AS signoz_metrics.time_series_v4_7d
ENGINE = Distributed('cluster', 'signoz_metrics', 'time_series_v4_7d', rand());

-- Gauge table
CREATE TABLE IF NOT EXISTS signoz_metrics.gauge_v4_6hrs (
    env String,
    temporality String,
    metric_name String,
    description String,
    unit String,
    type String,
    is_monotonic Boolean,
    fingerprint UInt64,
    unix_milli Int64,
    value Float64,
    labels String,
    attrs String,
    scope_attrs String,
    resource_attrs String,
    inserted_at_unix_milli Int64 DEFAULT toUnixTimestamp(now()) * 1000
) ENGINE = MergeTree()
ORDER BY (env, metric_name, fingerprint, unix_milli)
TTL toDateTime(inserted_at_unix_milli / 1000) + INTERVAL 6 HOUR
SETTINGS index_granularity = 8192;

-- Sum table
CREATE TABLE IF NOT EXISTS signoz_metrics.sum_v4_6hrs (
    env String,
    temporality String,
    metric_name String,
    description String,
    unit String,
    type String,
    is_monotonic Boolean,
    fingerprint UInt64,
    unix_milli Int64,
    value Float64,
    labels String,
    attrs String,
    scope_attrs String,
    resource_attrs String,
    inserted_at_unix_milli Int64 DEFAULT toUnixTimestamp(now()) * 1000
) ENGINE = MergeTree()
ORDER BY (env, metric_name, fingerprint, unix_milli)
TTL toDateTime(inserted_at_unix_milli / 1000) + INTERVAL 6 HOUR
SETTINGS index_granularity = 8192;

-- Histogram table
CREATE TABLE IF NOT EXISTS signoz_metrics.histogram_v4_6hrs (
    env String,
    temporality String,
    metric_name String,
    description String,
    unit String,
    type String,
    is_monotonic Boolean,
    fingerprint UInt64,
    unix_milli Int64,
    count UInt64,
    sum Float64,
    bucket_bounds Array(Float64),
    bucket_values Array(UInt64),
    exemplars String,
    labels String,
    attrs String,
    scope_attrs String,
    resource_attrs String,
    inserted_at_unix_milli Int64 DEFAULT toUnixTimestamp(now()) * 1000
) ENGINE = MergeTree()
ORDER BY (env, metric_name, fingerprint, unix_milli)
TTL toDateTime(inserted_at_unix_milli / 1000) + INTERVAL 6 HOUR
SETTINGS index_granularity = 8192;

-- Exp histogram table
CREATE TABLE IF NOT EXISTS signoz_metrics.exp_histogram_v4_6hrs (
    env String,
    temporality String,
    metric_name String,
    description String,
    unit String,
    type String,
    is_monotonic Boolean,
    fingerprint UInt64,
    unix_milli Int64,
    count UInt64,
    sum Float64,
    scale Int32,
    zero_count UInt64,
    positive_offset Int32,
    positive_bucket_values Array(UInt64),
    negative_offset Int32,
    negative_bucket_values Array(UInt64),
    exemplars String,
    labels String,
    attrs String,
    scope_attrs String,
    resource_attrs String,
    inserted_at_unix_milli Int64 DEFAULT toUnixTimestamp(now()) * 1000
) ENGINE = MergeTree()
ORDER BY (env, metric_name, fingerprint, unix_milli)
TTL toDateTime(inserted_at_unix_milli / 1000) + INTERVAL 6 HOUR
SETTINGS index_granularity = 8192;
