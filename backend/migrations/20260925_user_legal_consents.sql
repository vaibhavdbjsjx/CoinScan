-- =============================================================================
-- COINSCAN PRODUCTION POSTGRESQL / SUPABASE DATABASE SCHEMA MIGRATION
-- File: 20260925_user_legal_consents.sql
-- Description: Persistent table for user Terms & Conditions and Privacy Policy consent.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.user_legal_consents (
    user_id UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
    terms_version VARCHAR(50) NOT NULL,
    privacy_version VARCHAR(50) NOT NULL,
    accepted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_user_legal_consents_version ON public.user_legal_consents(terms_version, privacy_version);

ALTER TABLE public.user_legal_consents ENABLE ROW LEVEL SECURITY;

-- 1. Users can view their own legal consent record
CREATE POLICY "Users can view own legal consent"
    ON public.user_legal_consents FOR SELECT
    USING (auth.uid() = user_id);

-- 2. Users can insert their own legal consent record
CREATE POLICY "Users can insert own legal consent"
    ON public.user_legal_consents FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- 3. Users can update their own legal consent record (upon terms re-consent)
CREATE POLICY "Users can update own legal consent"
    ON public.user_legal_consents FOR UPDATE
    USING (auth.uid() = user_id);
