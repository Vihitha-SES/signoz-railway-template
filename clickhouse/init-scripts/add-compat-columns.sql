-- Add compatibility columns if collector still inserts inserted_at_unix_milli
-- Run on each ClickHouse data node (or against each shard)
-- Usage:
-- clickhouse-client --host <HOST> --user <USER> --password '<PASS>' < add-compat-columns.sql

ALTER TABLE IF EXISTS signoz_metrics.samples_v4
    ADD COLUMN IF NOT EXISTS inserted_at_unix_milli Int64 DEFAULT toUnixTimestamp(now()) * 1000 AFTER value;

ALTER TABLE IF EXISTS signoz_metrics.time_series_v4
    ADD COLUMN IF NOT EXISTS inserted_at_unix_milli Int64 DEFAULT toUnixTimestamp(now()) * 1000 AFTER labels;

ALTER TABLE IF EXISTS signoz_metrics.exemplars_v4
    ADD COLUMN IF NOT EXISTS inserted_at_unix_milli Int64 DEFAULT toUnixTimestamp(now()) * 1000 AFTER span_id;

-- Verify columns exist
SELECT
    table,
    name,
    type
FROM system.columns
WHERE database = 'signoz_metrics' AND name = 'inserted_at_unix_milli'
ORDER BY table;
