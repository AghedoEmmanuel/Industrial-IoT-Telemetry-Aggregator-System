CREATE TABLE IF NOT EXISTS telemetry_raw (
    sensor_id VARCHAR(64) NOT NULL,
    recorded_at TIMESTAMPTZ NOT NULL,
    value DOUBLE PRECISION NOT NULL
) PARTITION BY RANGE (recorded_at);

-- The first index supports sensor-specific time-series queries; the second
-- supports time-range queries that do not filter by sensor_id.
CREATE INDEX IF NOT EXISTS idx_telemetry_sensor_time
    ON telemetry_raw (sensor_id, recorded_at DESC);

CREATE INDEX IF NOT EXISTS idx_telemetry_recorded_at
    ON telemetry_raw (recorded_at);

-- Keep an idempotency receipt after queue processing so client retries cannot
-- enqueue the same reading again.
CREATE TABLE IF NOT EXISTS telemetry_ingest_receipts (
    idempotency_key UUID PRIMARY KEY,
    sensor_id VARCHAR(64) NOT NULL,
    recorded_at TIMESTAMPTZ NOT NULL,
    value DOUBLE PRECISION NOT NULL,
    received_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
);

-- Workers claim due rows with a lease; expired leases are eligible for reclaim.
CREATE TABLE IF NOT EXISTS telemetry_ingest_queue (
    idempotency_key UUID PRIMARY KEY
        REFERENCES telemetry_ingest_receipts (idempotency_key),
    attempt_count INTEGER NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
    next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    lease_token UUID,
    lease_expires_at TIMESTAMPTZ,
    last_error TEXT,
    CHECK ((lease_token IS NULL) = (lease_expires_at IS NULL))
);

CREATE INDEX IF NOT EXISTS idx_telemetry_ingest_queue_due
    ON telemetry_ingest_queue (next_attempt_at);

-- The cache outbox is written in the same transaction that stores raw data.
CREATE TABLE IF NOT EXISTS telemetry_cache_outbox (
    idempotency_key UUID PRIMARY KEY
        REFERENCES telemetry_ingest_receipts (idempotency_key),
    attempt_count INTEGER NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
    next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    lease_token UUID,
    lease_expires_at TIMESTAMPTZ,
    last_error TEXT,
    CHECK ((lease_token IS NULL) = (lease_expires_at IS NULL))
);

CREATE INDEX IF NOT EXISTS idx_telemetry_cache_outbox_due
    ON telemetry_cache_outbox (next_attempt_at);

-- Failed work is retained for inspection and manual replay instead of discarded.
CREATE TABLE IF NOT EXISTS telemetry_dead_letters (
    idempotency_key UUID NOT NULL
        REFERENCES telemetry_ingest_receipts (idempotency_key),
    failure_stage TEXT NOT NULL
        CHECK (failure_stage IN ('postgres', 'redis')),
    attempt_count INTEGER NOT NULL CHECK (attempt_count > 0),
    last_error TEXT NOT NULL,
    failed_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    PRIMARY KEY (idempotency_key, failure_stage)
);

CREATE OR REPLACE PROCEDURE maintain_telemetry_partitions(
    days_in_past INT,
    days_in_future INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    day_offset INT;
    target_date DATE;
    partition_name TEXT;
    partition_start TIMESTAMPTZ;
    partition_end TIMESTAMPTZ;
BEGIN
    IF days_in_past IS NULL
        OR days_in_future IS NULL
        OR days_in_past < 0
        OR days_in_future < 0
    THEN
        RAISE EXCEPTION 'Partition window values must be non-negative';
    END IF;

    -- Create partitions from days_in_past before today through
    -- days_in_future after today, with all day boundaries in UTC.
    FOR day_offset IN -days_in_past..days_in_future LOOP
        target_date := (CURRENT_TIMESTAMP AT TIME ZONE 'UTC')::DATE + day_offset;
        partition_name := 'telemetry_raw_y'
            || TO_CHAR(target_date, 'YYYY')
            || 'm' || TO_CHAR(target_date, 'MM')
            || 'd' || TO_CHAR(target_date, 'DD');
        partition_start := target_date::TIMESTAMP AT TIME ZONE 'UTC';
        partition_end := (target_date + 1)::TIMESTAMP AT TIME ZONE 'UTC';

        EXECUTE FORMAT(
            'CREATE TABLE IF NOT EXISTS %I PARTITION OF telemetry_raw '
            'FOR VALUES FROM (%L) TO (%L)',
            partition_name,
            partition_start,
            partition_end
        );
    END LOOP;
END;
$$;

-- Run this procedure on a schedule to keep the rolling partition window current.
CALL maintain_telemetry_partitions(2, 60);
