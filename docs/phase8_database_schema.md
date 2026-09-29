# CoinScan Phase 8: PostgreSQL / Supabase Database Schema

**Date:** 2026-08-27  
**Author:** Senior Staff Database & Security Architect  
**Document Version:** 1.0.0  
**Status:** **ACTIVE / VERIFIED**

---

## 1. Database Architecture & ERD Overview

```
+---------------------------------------------------------------------------------------------------+
|                                     COINSCAN DATABASE SCHEMA                                      |
+---------------------------------------------------------------------------------------------------+

     +-----------------------+                    +---------------------------+
     |      auth.users       |                    |    subscription_events    |
     |  (Supabase Managed)   |                    +---------------------------+
     +-----------+-----------+                    | id (UUID, PK)             |
                 | 1:1                            | event_id (VARCHAR, UNIQUE)|
                 v                                | app_user_id (UUID, FK)    |
     +-----------------------+                    | event_type (VARCHAR)      |
     |     public.users      |                    | product_id (VARCHAR)      |
     +-----------------------+                    | store (VARCHAR)           |
     | id (UUID, PK)         |<-----------+       | environment (VARCHAR)     |
     | email (VARCHAR)       |            |       | received_at (TIMESTAMPTZ) |
     | full_name (VARCHAR)   |            |       | raw_payload (JSONB)       |
     | avatar_url (TEXT)     |            |       +---------------------------+
     | created_at (TSTZ)     |            |
     | updated_at (TSTZ)     |            |
     +-----------+-----------+            |
                 |                        |
         +-------+-------+----------------+----------------+
         | 1:N           | 1:1            | 1:N            | 1:N
         v               v                v                v
+----------------+ +----------------+ +----------------+ +----------------+
| subscriptions  | | entitlements   | |   scan_usage   | |  scan_history  |
+----------------+ +----------------+ +----------------+ +----------------+
| id (UUID, PK)  | | user_id (UUID) | | id (UUID, PK)  | | id (UUID, PK)  |
| user_id (UUID) | | tier (VARCHAR) | | user_id (UUID) | | user_id (UUID) |
| original_tx_id | | status (VARCHR)| | scan_date(DATE)| | scanned_at(TZ) |
| product_id     | | daily_limit    | | scan_count(INT)| | coin_name      |
| store (apple)  | | expires_at     | | created_at(TZ) | | country        |
| status (active)| | updated_at(TZ) | | updated_at(TZ) | | denomination   |
| starts_at      | +----------------+ +----------------+ | year           |
| current_end_at |                                       | numista_id     |
| cancel_at_end  |                                       | confidence     |
| is_sandbox     |                                       | status_label   |
+----------------+                                       | front_image_url|
                                                         | result_json    |
                                                         +----------------+

     +-----------------------+                    +---------------------------+
     |       api_keys        | 1:N                |       api_key_usage       |
     +-----------------------+                    +---------------------------+
     | id (UUID, PK)         |------------------->| id (UUID, PK)             |
     | user_id (UUID, FK)    |                    | api_key_id (UUID, FK)     |
     | key_prefix (VARCHAR)  |                    | usage_month (DATE)        |
     | key_hash (VARCHAR, UQ)|                    | request_count (INT)       |
     | name (VARCHAR)        |                    | success_count (INT)       |
     | tier (VARCHAR)        |                    | rate_limit_hits (INT)     |
     | monthly_limit (INT)   |                    | updated_at (TIMESTAMPTZ)  |
     | is_active (BOOLEAN)   |                    +---------------------------+
     | created_at (TSTZ)     |
     | last_used_at (TSTZ)   |
     +-----------------------+
```

---

## 2. Production PostgreSQL DDL Script

```sql
-- =============================================================================
-- COINSCAN PRODUCTION POSTGRESQL SCHEMA SPECIFICATION
-- =============================================================================

-- 1. Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 2. Public User Profile Table (linked 1:1 with Supabase auth.users)
CREATE TABLE IF NOT EXISTS public.users (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email VARCHAR(255) NOT NULL,
    full_name VARCHAR(255),
    avatar_url TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_users_email ON public.users(email);

-- 3. Entitlements Table (Server-Authoritative Tier State)
CREATE TYPE subscription_tier_enum AS ENUM ('limited', 'plus', 'pro', 'enterprise');
CREATE TYPE subscription_status_enum AS ENUM ('none', 'trial', 'active', 'grace', 'billing_retry', 'cancelled', 'expired', 'revoked');

CREATE TABLE IF NOT EXISTS public.entitlements (
    user_id UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
    tier subscription_tier_enum NOT NULL DEFAULT 'limited',
    status subscription_status_enum NOT NULL DEFAULT 'none',
    daily_scan_limit INT NOT NULL DEFAULT 3, -- 3 for limited, 30 for plus, 100 for pro
    advanced_recognition_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    market_valuation_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    expires_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 4. Subscriptions Table (Active & Historical In-App Purchases)
CREATE TABLE IF NOT EXISTS public.subscriptions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    original_transaction_id VARCHAR(255) NOT NULL,
    store VARCHAR(50) NOT NULL DEFAULT 'app_store', -- 'app_store', 'play_store', 'stripe'
    product_id VARCHAR(255) NOT NULL,
    tier subscription_tier_enum NOT NULL,
    status subscription_status_enum NOT NULL DEFAULT 'active',
    period VARCHAR(50) NOT NULL DEFAULT 'monthly', -- 'monthly', 'yearly'
    starts_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    current_period_end TIMESTAMPTZ NOT NULL,
    cancel_at_period_end BOOLEAN NOT NULL DEFAULT FALSE,
    is_sandbox BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_subscriptions_original_tx UNIQUE (original_transaction_id)
);

CREATE INDEX IF NOT EXISTS idx_subscriptions_user ON public.subscriptions(user_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_status ON public.subscriptions(status);

-- 5. Subscription Events Log (Idempotent Webhook Processing)
CREATE TABLE IF NOT EXISTS public.subscription_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    event_id VARCHAR(255) NOT NULL UNIQUE, -- RevenueCat event ID or Apple notification UUID
    app_user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
    event_type VARCHAR(100) NOT NULL, -- INITIAL_PURCHASE, RENEWAL, CANCELLATION, EXPIRATION, etc.
    product_id VARCHAR(255),
    store VARCHAR(50),
    environment VARCHAR(50), -- 'SANDBOX', 'PRODUCTION'
    received_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    raw_payload JSONB NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_sub_events_event_id ON public.subscription_events(event_id);
CREATE INDEX IF NOT EXISTS idx_sub_events_user ON public.subscription_events(app_user_id);

-- 6. Server-Authoritative Daily Scan Quota Tracking
CREATE TABLE IF NOT EXISTS public.scan_usage (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    scan_date DATE NOT NULL DEFAULT (CURRENT_TIMESTAMP AT TIME ZONE 'UTC')::DATE,
    scan_count INT NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_user_scan_date UNIQUE (user_id, scan_date)
);

CREATE INDEX IF NOT EXISTS idx_scan_usage_user_date ON public.scan_usage(user_id, scan_date);

-- 7. User Scan History (Cloud Backup & Sync)
CREATE TABLE IF NOT EXISTS public.scan_history (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    scanned_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    coin_name VARCHAR(255),
    country VARCHAR(100),
    denomination VARCHAR(100),
    year VARCHAR(50),
    numista_id INT,
    confidence_score NUMERIC(5, 4),
    status_label VARCHAR(50),
    front_image_url TEXT,
    reverse_image_url TEXT,
    result_json JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_scan_history_user ON public.scan_history(user_id, scanned_at DESC);

-- 8. Developer API Key Management
CREATE TABLE IF NOT EXISTS public.api_keys (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    key_prefix VARCHAR(16) NOT NULL, -- e.g. "coinscan_live_4a"
    key_hash VARCHAR(64) NOT NULL UNIQUE, -- SHA-256 hash of secret key
    name VARCHAR(255) NOT NULL DEFAULT 'Default API Key',
    tier subscription_tier_enum NOT NULL DEFAULT 'plus',
    monthly_request_limit INT NOT NULL DEFAULT 5000,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_used_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_api_keys_hash ON public.api_keys(key_hash);
CREATE INDEX IF NOT EXISTS idx_api_keys_user ON public.api_keys(user_id);

-- 9. Developer API Key Monthly Usage Aggregation
CREATE TABLE IF NOT EXISTS public.api_key_usage (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    api_key_id UUID NOT NULL REFERENCES public.api_keys(id) ON DELETE CASCADE,
    usage_month DATE NOT NULL, -- Truncated to 1st of month: YYYY-MM-01
    request_count INT NOT NULL DEFAULT 0,
    success_count INT NOT NULL DEFAULT 0,
    rate_limit_hits INT NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_api_key_month UNIQUE (api_key_id, usage_month)
);

CREATE INDEX IF NOT EXISTS idx_api_key_usage ON public.api_key_usage(api_key_id, usage_month);
```

---

## 3. Row Level Security (RLS) Policies

```sql
-- Enable RLS on all user data tables
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.entitlements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.scan_usage ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.scan_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.api_keys ENABLE ROW LEVEL SECURITY;

-- Users can only read/update their own profile
CREATE POLICY "Users can view own profile" ON public.users
    FOR SELECT USING (auth.uid() = id);

CREATE POLICY "Users can update own profile" ON public.users
    FOR UPDATE USING (auth.uid() = id);

-- Entitlements: Read-only for authenticated user; writes restricted to service_role
CREATE POLICY "Users can view own entitlement" ON public.entitlements
    FOR SELECT USING (auth.uid() = user_id);

-- Scan History: Users can CRUD their own history
CREATE POLICY "Users can view own history" ON public.scan_history
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own history" ON public.scan_history
    FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own history" ON public.scan_history
    FOR DELETE USING (auth.uid() = user_id);

-- API Keys: Users manage their own API keys
CREATE POLICY "Users can view own API keys" ON public.api_keys
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can create own API keys" ON public.api_keys
    FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can deactivate own API keys" ON public.api_keys
    FOR UPDATE USING (auth.uid() = user_id);
```
