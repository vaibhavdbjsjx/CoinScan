-- =============================================================================
-- COINSCAN PRODUCTION POSTGRESQL / SUPABASE DATABASE SCHEMA MIGRATION
-- File: 20260830_phase11_production_schema.sql
-- Description: Complete production schema with strict multi-tenant Row Level Security (RLS).
-- =============================================================================

-- 1. Extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 2. Custom Types / Enums
DO $$ BEGIN
    CREATE TYPE subscription_tier_enum AS ENUM ('free', 'plus', 'pro', 'enterprise');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE subscription_status_enum AS ENUM (
        'none', 'trial', 'active', 'grace', 'billing_retry', 'cancelled', 'expired', 'revoked'
    );
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE feedback_category_enum AS ENUM (
        'recognition_incorrect', 'valuation_incorrect', 'camera_problem', 'gallery_problem',
        'subscription_problem', 'app_crash', 'performance', 'feature_request', 'other'
    );
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- -----------------------------------------------------------------------------
-- 3. Public User Profiles Table (1:1 with auth.users)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.users (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email VARCHAR(255) NOT NULL,
    display_name VARCHAR(255),
    avatar_url TEXT,
    preferred_currency VARCHAR(10) NOT NULL DEFAULT 'USD',
    locale VARCHAR(20) NOT NULL DEFAULT 'en-US',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_users_email ON public.users(email);

-- -----------------------------------------------------------------------------
-- 4. Entitlements Table (Server-Authoritative Subscription Tier)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.entitlements (
    user_id UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
    tier subscription_tier_enum NOT NULL DEFAULT 'free',
    status subscription_status_enum NOT NULL DEFAULT 'none',
    daily_scan_limit INT NOT NULL DEFAULT 3,
    active_subscription_id UUID,
    expires_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_entitlements_tier ON public.entitlements(tier);

-- -----------------------------------------------------------------------------
-- 5. Subscriptions Table (Store / IAP Receipts)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    original_transaction_id VARCHAR(255) NOT NULL,
    product_id VARCHAR(255) NOT NULL,
    store VARCHAR(50) NOT NULL, -- 'apple_app_store', 'google_play', 'stripe'
    status subscription_status_enum NOT NULL DEFAULT 'active',
    starts_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    current_period_start TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    current_period_end TIMESTAMPTZ NOT NULL,
    cancel_at_period_end BOOLEAN NOT NULL DEFAULT FALSE,
    is_sandbox BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_subscriptions_user_id ON public.subscriptions(user_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_orig_tx ON public.subscriptions(original_transaction_id);

-- -----------------------------------------------------------------------------
-- 6. Subscription Events Table (Idempotent Webhook Log)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.subscription_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id VARCHAR(255) NOT NULL UNIQUE, -- Idempotency Key from RevenueCat / Apple
    app_user_id VARCHAR(255) NOT NULL,
    event_type VARCHAR(100) NOT NULL,
    product_id VARCHAR(255),
    store VARCHAR(50),
    environment VARCHAR(50) NOT NULL DEFAULT 'PRODUCTION',
    raw_payload JSONB NOT NULL,
    received_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_sub_events_event_id ON public.subscription_events(event_id);
CREATE INDEX IF NOT EXISTS idx_sub_events_user_id ON public.subscription_events(app_user_id);

-- -----------------------------------------------------------------------------
-- 7. Scan Usage Table (Daily Quota Counting)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.scan_usage (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    scan_date DATE NOT NULL, -- Format: YYYY-MM-DD (in UTC)
    scan_count INT NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_user_scan_date UNIQUE (user_id, scan_date)
);

CREATE INDEX IF NOT EXISTS idx_scan_usage_lookup ON public.scan_usage(user_id, scan_date);

-- -----------------------------------------------------------------------------
-- 8. Scan History Table
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.scan_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    scanned_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    coin_name VARCHAR(255),
    country VARCHAR(100),
    denomination VARCHAR(100),
    year VARCHAR(20),
    mint_mark VARCHAR(50),
    grade VARCHAR(50),
    confidence_score NUMERIC(5, 4),
    numista_id INT,
    status_label VARCHAR(50) NOT NULL,
    front_image_url TEXT,
    reverse_image_url TEXT,
    result_json JSONB
);

CREATE INDEX IF NOT EXISTS idx_scan_history_user ON public.scan_history(user_id, scanned_at DESC);

-- -----------------------------------------------------------------------------
-- 9. Collection Vault & Items
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.collection_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    coin_name VARCHAR(255) NOT NULL,
    country VARCHAR(100) NOT NULL,
    denomination VARCHAR(100) NOT NULL,
    year INT,
    mint_mark VARCHAR(50),
    composition VARCHAR(150),
    grade VARCHAR(50),
    numista_id INT,
    purchase_price NUMERIC(12, 2),
    purchase_date DATE,
    currency_code VARCHAR(10) NOT NULL DEFAULT 'USD',
    initial_valuation_snapshot NUMERIC(12, 2),
    current_estimated_value NUMERIC(12, 2),
    notes TEXT,
    front_image_url TEXT,
    reverse_image_url TEXT,
    is_favorite BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_collection_user ON public.collection_items(user_id, created_at DESC);

-- -----------------------------------------------------------------------------
-- 10. Developer API Keys & Usage Tracking
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.api_keys (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    key_prefix VARCHAR(32) NOT NULL,
    key_hash VARCHAR(128) NOT NULL UNIQUE,
    name VARCHAR(255) NOT NULL,
    tier subscription_tier_enum NOT NULL DEFAULT 'free',
    monthly_limit INT NOT NULL DEFAULT 500,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_used_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_api_keys_hash ON public.api_keys(key_hash);
CREATE INDEX IF NOT EXISTS idx_api_keys_user ON public.api_keys(user_id);

CREATE TABLE IF NOT EXISTS public.api_key_usage (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    api_key_id UUID NOT NULL REFERENCES public.api_keys(id) ON DELETE CASCADE,
    usage_month DATE NOT NULL, -- 1st of each month (YYYY-MM-01)
    request_count INT NOT NULL DEFAULT 0,
    success_count INT NOT NULL DEFAULT 0,
    rate_limit_hits INT NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_key_usage_month UNIQUE (api_key_id, usage_month)
);

-- -----------------------------------------------------------------------------
-- 11. User Feedback & Support Submissions
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.feedback (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
    category feedback_category_enum NOT NULL,
    title VARCHAR(200) NOT NULL,
    description TEXT NOT NULL,
    app_version VARCHAR(50) NOT NULL,
    platform VARCHAR(50) NOT NULL,
    request_id VARCHAR(100),
    client_ip VARCHAR(50),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- -----------------------------------------------------------------------------
-- 12. Security Audit Events Log
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.security_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
    event_type VARCHAR(100) NOT NULL, -- e.g. 'tier_spoofing_attempt', 'unauthorized_idor_access'
    ip_address VARCHAR(50),
    user_agent TEXT,
    details JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_security_events_type ON public.security_events(event_type, created_at DESC);

-- =============================================================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- Strict Multi-Tenant Isolation: User A can NEVER view/edit User B's records.
-- =============================================================================

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.entitlements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscription_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.scan_usage ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.scan_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.collection_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.api_keys ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.api_key_usage ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.security_events ENABLE ROW LEVEL SECURITY;

-- 1. Users policies
CREATE POLICY "Users can view own profile"
    ON public.users FOR SELECT
    USING (auth.uid() = id);

CREATE POLICY "Users can update own profile"
    ON public.users FOR UPDATE
    USING (auth.uid() = id);

-- 2. Entitlements policies (Users read-only; server mutates)
CREATE POLICY "Users can view own entitlements"
    ON public.entitlements FOR SELECT
    USING (auth.uid() = user_id);

-- 3. Subscriptions policies
CREATE POLICY "Users can view own subscriptions"
    ON public.subscriptions FOR SELECT
    USING (auth.uid() = user_id);

-- 4. Scan Usage policies
CREATE POLICY "Users can view own scan usage"
    ON public.scan_usage FOR SELECT
    USING (auth.uid() = user_id);

-- 5. Scan History policies (Full CRUD on own records)
CREATE POLICY "Users can view own scan history"
    ON public.scan_history FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own scan history"
    ON public.scan_history FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own scan history"
    ON public.scan_history FOR DELETE
    USING (auth.uid() = user_id);

-- 6. Collection Items policies (Full CRUD on own vault)
CREATE POLICY "Users can view own collection items"
    ON public.collection_items FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own collection items"
    ON public.collection_items FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own collection items"
    ON public.collection_items FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own collection items"
    ON public.collection_items FOR DELETE
    USING (auth.uid() = user_id);

-- 7. Developer API Keys policies
CREATE POLICY "Users can view own API keys"
    ON public.api_keys FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own API keys"
    ON public.api_keys FOR DELETE
    USING (auth.uid() = user_id);

-- 8. Feedback policies
CREATE POLICY "Users can insert feedback"
    ON public.feedback FOR INSERT
    WITH CHECK (auth.uid() = user_id OR user_id IS NULL);

CREATE POLICY "Users can view own feedback"
    ON public.feedback FOR SELECT
    USING (auth.uid() = user_id);

-- =============================================================================
-- STORAGE BUCKET RLS SPECIFICATION (Supabase Storage)
-- =============================================================================
-- Private Bucket: 'coinscan-user-vaults'
-- Path structure: {user_id}/{item_id}.jpg
--
-- Storage Policies (executed in Supabase Storage API):
-- 1. Read Policy:
--    CREATE POLICY "Users can read own vault images"
--    ON storage.objects FOR SELECT
--    USING (bucket_id = 'coinscan-user-vaults' AND (storage.foldername(name))[1] = auth.uid()::text);
--
-- 2. Insert Policy (Max 10MB, JPEG/PNG/WebP only):
--    CREATE POLICY "Users can upload own vault images"
--    ON storage.objects FOR INSERT
--    WITH CHECK (
--        bucket_id = 'coinscan-user-vaults'
--        AND (storage.foldername(name))[1] = auth.uid()::text
--    );
--
-- 3. Delete Policy:
--    CREATE POLICY "Users can delete own vault images"
--    ON storage.objects FOR DELETE
--    USING (bucket_id = 'coinscan-user-vaults' AND (storage.foldername(name))[1] = auth.uid()::text);
