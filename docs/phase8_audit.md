# CoinScan Phase 8: Repository & Production Readiness Audit

**Date:** 2026-08-27  
**Author:** Senior Staff Platform, Security & Payments Engineer  
**Document Version:** 1.0.0  
**Status:** **ACTIVE / VERIFIED**

---

## 1. Executive Summary

This audit performs an exhaustive, component-by-component inspection of the CoinScan repository following the completion of Phase 7. The primary goal is to establish a rigorous boundary between **what is genuinely production-ready**, **what is an architectural abstraction/scaffolding**, and **what remains simulated or mock data**.

CoinScan has a functional Flutter mobile UI and a real multi-sided backend recognition engine powered by Google Gemini, OCR heuristics, Numista v3 integration, and live metal/FX valuation. However, prior to Phase 8, user authentication, subscription receipt validation, and database persistence were implemented as local in-memory or development prototypes.

---

## 2. Component-by-Component State Matrix

| Component | Current Implementation | Production Readiness | Gap / Risk to Resolve in Phase 8 |
|---|---|---|---|
| **Flutter Mobile Capture** | Real camera (`camera` pkg) + gallery (`image_picker`), 3-step capture (Front, Reverse, Edge) | **Production-Ready** | None for core capture. |
| **Flutter Recognition Client** | `HttpRecognitionService` sending multipart form-data to backend via `AppConfig` | **Production-Ready** | Needs auth token/JWT header injection alongside API keys. |
| **Paywall Screen** | `PaywallScreen` with tier matrix, toggle, restore button, Apple legal disclaimers | **UI Ready / Dev Backed** | Currently calls `DevSubscriptionService` in-memory mock purchase. |
| **Subscription Entitlements** | `entitlement_models.dart` & `subscription_service.dart` | **Interface Ready / Dev Backed** | Client-side tracking is in-memory; needs RevenueCat/StoreKit SDK & server-authoritative enforcement. |
| **Scan History UI & Storage** | `scan_history_screen.dart` + `scan_history_service.dart` (JSON file storage via `path_provider`) | **Functional Local** | Local-only JSON storage. Cloud sync and account binding required for multi-device users. |
| **User Authentication** | `LoginScreen` in onboarding | **Simulated UI** | `_handleEmailLogin` and `_handleOAuthLogin` simulate delay without real Supabase/Apple Auth backend. |
| **Secondary Features UI** | `MockApi` (Marketplace, Vault Portfolio, Lessons, Achievements) | **Demo / Fixture Data** | Feeds UI previews. Must remain isolated from production scanning path. |
| **Backend Recognition Pipeline** | `backend/app/api/recognition.py`, `evidence_engine.py`, `numista/client.py`, `valuation_service.py` | **Production-Ready** | Working pipeline with multimodal vision, OCR heuristics, Numista v3 catalog lookup, and live spot/FX. |
| **Backend Auth & Rate Limit** | `backend/app/security/auth.py` + `rate_limit.py` | **Partial / Dev** | Checks static API keys from JSON env variable and IP rate limits. Lacks user account/JWT auth and database-backed quotas. |
| **Backend Deployment** | `backend/Dockerfile` (non-root, health checks) + `cloudbuild.yaml` | **Deployment Ready** | Container and Cloud Run build specs verified. Requires live Cloud Run provisioning and Secret Manager configuration. |

---

## 3. Detailed Gap & Risk Analysis

### 3.1 Security & Client-Side Trust Vulnerabilities
1. **Client-Controlled Claims:** If a client could dictate its tier via headers (e.g. `X-Tier: pro`), an attacker could bypass billing entirely.
   - *Phase 8 Solution:* The backend must enforce **server-authoritative entitlements**. Subscriptions and scan limits must be resolved from cryptographically verified user tokens or verified server-side webhook records.
2. **API Secret Exposure in Flutter:** The Flutter client must never embed administrative API secrets (`SUPABASE_SERVICE_ROLE_KEY`, `NUMISTA_API_KEY`, etc.).
   - *Phase 8 Solution:* All third-party secrets remain strictly encapsulated within the FastAPI backend on Google Cloud Run.

### 3.2 Payment & In-App Purchase Risks
1. **Apple Guideline 3.1.1 Compliance:** iOS apps selling digital features (coin identification quotas, valuation data) MUST use Apple In-App Purchase. Stripe or external web checkout inside the iOS app is strictly prohibited and would lead to immediate App Store rejection.
   - *Phase 8 Solution:* Standardize on Apple StoreKit 2 via the **RevenueCat** subscription infrastructure layer.
2. **Subscription Idempotency & Webhook Race Conditions:** Subscriptions can experience network interruptions, renewals, refunds, or chargebacks.
   - *Phase 8 Solution:* Build an idempotent backend webhook receiver (`/v1/webhooks/revenuecat`) with duplicate event rejection and transactional database state updates.

### 3.3 Database & Account Architecture
1. **Unpersisted Quotas:** Currently, daily scan quotas are tracked in the client's local memory, which resets on app reinstall or clearing data.
   - *Phase 8 Solution:* Design a PostgreSQL / Supabase database schema with atomic usage tracking (`scan_usage` table) keyed by `user_id` with UTC midnight reset boundaries and concurrency lock protection.

---

## 4. Recommended Phase 8 Implementation Sequence

1. **Step 2 & 3: Payment & Pricing Architecture:** Finalize RevenueCat decision, product IDs, entitlements, unit economics, and worldwide pricing strategy (`docs/phase8_pricing_strategy.md`).
2. **Step 4 & 5: Database Schema & Auth Architecture:** Formalize PostgreSQL / Supabase schema for `users`, `subscriptions`, `entitlements`, `scan_usage`, `scan_history`, and `api_keys` (`docs/phase8_database_schema.md`).
3. **Step 6 & 7: Server Synchronization & Quota Enforcement:** Implement RevenueCat webhook processor, database-backed user authentication middleware, and server-side atomic quota engine with concurrency safety.
4. **Step 8: Separate Developer API-Key Product:** Build cryptographically secure SHA-256 hashed API key management (`coinscan_live_...`) with rate and usage limits.
5. **Step 9 & 10: Hosting Decision & Domain Architecture:** Document Cloud Run vs alternatives (`docs/phase8_hosting_decision.md`) and custom domain topology (`api.coinscan.app`).
6. **Step 11, 12 & 13: Secret Audits, Compliance & Demo Data Isolation:** Update `.env.example`, generate App Store monetization checklist (`docs/phase8_app_store_monetization_checklist.md`), and audit demo data boundaries (`docs/phase8_demo_data_audit.md`).
7. **Step 14 & 16: End-to-End Verification & Automated Testing:** Add comprehensive tests across auth, webhooks, idempotency, concurrent quota races, and API key lifecycles.
