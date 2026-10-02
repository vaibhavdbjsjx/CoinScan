-- =============================================================================
-- COINSCAN MIGRATION: 20260930_guest_scan_usage.sql
-- Server-authoritative daily scan quota for signed-out (guest) users.
--
-- Guests are NOT users: no row is ever created in public.users or scan_usage for
-- them. Each row is keyed by an HMAC-SHA256 of a network or install identifier,
-- computed with a server-side secret (GUEST_QUOTA_HMAC_SECRET). Raw IP addresses
-- and raw install IDs are never stored. Rows are only needed for the current day
-- and are pruned by the backend after a short retention window.
--
-- scan_date is always computed by the API as the current UTC date; the database
-- time zone plays no part. Counters are changed only by the API, with one atomic
-- conditional upsert per scan (see backend/app/security/guest_quota.py).
--
-- Safe to run more than once.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.guest_scan_usage (
    -- lowercase hex HMAC-SHA256; anything else (e.g. a raw address) is refused
    key_hash CHAR(64) NOT NULL CHECK (key_hash ~ '^[0-9a-f]{64}$'),
    key_kind VARCHAR(16) NOT NULL CHECK (key_kind IN ('install', 'network')),
    scan_date DATE NOT NULL,             -- UTC day
    scan_count INT NOT NULL DEFAULT 0 CHECK (scan_count >= 0),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (key_hash, scan_date)
);

-- Pruning deletes by date.
CREATE INDEX IF NOT EXISTS idx_guest_scan_usage_date ON public.guest_scan_usage(scan_date);

-- Only the API (connecting as the table owner through DATABASE_URL) uses this
-- table. Row level security with no policies denies the Supabase client roles,
-- and their table privileges are removed as well, so the public Data API can
-- neither read nor change guest counters.
ALTER TABLE public.guest_scan_usage ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
        EXECUTE 'REVOKE ALL ON TABLE public.guest_scan_usage FROM anon';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
        EXECUTE 'REVOKE ALL ON TABLE public.guest_scan_usage FROM authenticated';
    END IF;
END
$$;
