-- Traces Tables for SigNoz v0.144.2

-- Drop existing tables first
DROP TABLE IF EXISTS signoz_traces.distributed_spans;
DROP TABLE IF EXISTS signoz_traces.span_index;
DROP TABLE IF EXISTS signoz_traces.spans;

-- Main spans table
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
TTL startTime + INTERVAL 72 HOUR
SETTINGS index_granularity = 8192;

-- Distributed traces table
CREATE TABLE signoz_traces.distributed_spans AS signoz_traces.spans
ENGINE = Distributed('cluster', 'signoz_traces', 'spans', rand());

-- Index table for quick lookups
CREATE TABLE signoz_traces.span_index (
    traceID String,
    spanID String,
    startTime DateTime,
    serviceName String,
    operationName String
) ENGINE = MergeTree()
ORDER BY (traceID, startTime)
TTL startTime + INTERVAL 72 HOUR
SETTINGS index_granularity = 8192;
