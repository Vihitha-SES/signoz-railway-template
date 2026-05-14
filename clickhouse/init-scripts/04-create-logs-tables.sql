-- Logs Tables for SigNoz v0.144.2

-- Main logs table
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
TTL timestamp + INTERVAL 7 DAY
SETTINGS index_granularity = 8192;

-- Distributed logs table
CREATE TABLE IF NOT EXISTS signoz_logs.distributed_logs AS signoz_logs.logs
ENGINE = Distributed('cluster', 'signoz_logs', 'logs', rand());

-- Logs index for fast lookups
CREATE TABLE IF NOT EXISTS signoz_logs.logs_index (
    timestamp DateTime,
    service_name String,
    severity_text String,
    body String
) ENGINE = MergeTree()
ORDER BY (service_name, timestamp, severity_text)
TTL timestamp + INTERVAL 7 DAY
SETTINGS index_granularity = 8192;
