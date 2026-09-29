# CoinScan Phase 9: Comprehensive Initial Repository Audit

**Date:** 2026-08-27  
**Author:** Principal Platform, Mobile & Security Engineer  
**Document Version:** 1.0.0  
**Status:** **AUDIT VERIFIED**

---

## 1. Executive Summary

This initial audit establishes an unvarnished, line-by-line inspection of the CoinScan repository across the Flutter client, FastAPI backend, test suites, deployment scripts, and documentation before making Phase 9 changes.

Every component is explicitly classified under one of six standardized categories:
1. **`REAL + VERIFIED`**: Complete, functional, covered by automated test execution.
2. **`REAL CODE BUT EXTERNAL CONFIGURATION REQUIRED`**: Implemented correctly in code, but blocked on third-party credentials/accounts (e.g. Apple Developer IAP, RevenueCat dashboard, live Supabase project).
3. **`MOCK / DEVELOPMENT ONLY`**: Development fixture or in-memory stub used for local testing and isolated UI showcases.
4. **`BROKEN`**: Code containing logical errors or failure modes requiring immediate fix.
5. **`MISSING`**: Required production feature or error-recovery logic not yet written.
6. **`UNVERIFIED`**: Cannot be physically executed in the current environment (e.g. physical iPhone StoreKit sandbox purchase).

---

## 2. Component-by-Component Classification Matrix

| Component | Subsystem / File | Classification | Exact Status & Findings |
|---|---|---|---|
| **Camera Viewfinder & Hardware Capture** | `lib/features/scan/scan_screen.dart` | **`REAL + VERIFIED`** | Uses Flutter `camera` controller for hardware obverse, reverse, and optional edge capture with flashlight controls. |
| **Gallery Image Import** | `lib/features/scan/scan_screen.dart` | **`REAL + VERIFIED`** | Uses `image_picker` to load user photos into `CapturedCoinImage` records. |
| **Flutter Recognition Client** | `lib/core/recognition/http_recognition_service.dart` | **`REAL + VERIFIED`** | Sends real multipart requests to FastAPI backend with timeout, status handling, and diagnostic reporting. |
| **Scan History (Local JSON)** | `lib/core/storage/scan_history_service.dart` | **`REAL + VERIFIED`** | Persists real scans locally using `path_provider` to JSON storage; loads, filters, and deletes records. |
| **Scan History UI** | `lib/features/scan/scan_history_screen.dart` | **`REAL + VERIFIED`** | Full Flutter UI with thumbnail previews, confidence badges, swipe-to-delete, clear all, and modal detail sheet. |
| **Paywall Screen UI** | `lib/features/subscription/paywall_screen.dart` | **`REAL + VERIFIED`** | Polished paywall UI with monthly/yearly billing toggle, tier feature matrix, restore purchases handling, and Apple legal text. |
| **Legal Screen & Compliance UI** | `lib/features/profile/legal_screen.dart` | **`REAL + VERIFIED`** | In-app Privacy Policy and Terms of Service viewer with section navigation. |
| **In-Memory Subscription Dev Adapter** | `lib/core/subscriptions/subscription_service.dart` | **`MOCK / DEVELOPMENT ONLY`** | `DevSubscriptionService` provides in-memory tier switching and simulated purchases for local dev. Must be decoupled from production release builds. |
| **Backend Recognition Pipeline** | `backend/app/api/recognition.py` | **`REAL + VERIFIED`** | Multipart image ingestion, Laplacian sharpness check, multimodal AI (Gemini/OpenAI), OCR signals, Numista v3 integration, 4-layer valuation, and FX conversion. |
| **Server-Authoritative Quota Engine** | `backend/app/security/quota_service.py` | **`REAL + VERIFIED`** | Thread-safe atomic locking (`asyncio.Lock()`) with UTC date boundaries. *Issue to fix in Phase 9: Quota should only be deducted if recognition succeeds or validly completes, not on server 500 error.* |
| **Server Auth & API Key Middleware** | `backend/app/security/auth.py`, `jwt_auth.py` | **`REAL + VERIFIED`** | Unified authenticator resolving Supabase JWT tokens, developer API keys (`coinscan_live_...`), and dev keys. Discards client `X-Tier` claims. |
| **Developer API Key Management** | `backend/app/security/api_key_service.py` | **`REAL + VERIFIED`** | Cryptographic key generation, SHA-256 hash storage, validation, revocation, and rate limiting. |
| **RevenueCat & App Store Webhook Ingestion** | `backend/app/api/webhooks.py` | **`REAL + VERIFIED`** | Ingestion endpoint (`POST /v1/webhooks/revenuecat`) with bearer signature validation, event routing, and duplicate idempotency. |
| **PostgreSQL & Supabase DDL Schema** | `docs/phase8_database_schema.md` | **`REAL CODE BUT EXTERNAL CONFIGURATION REQUIRED`** | Complete DDL script with indexes, constraints, and RLS policies ready to execute on Supabase. |
| **Live Supabase PostgreSQL Database** | External Cloud | **`REAL CODE BUT EXTERNAL CONFIGURATION REQUIRED`** | Requires live Supabase project creation and URL/key injection. |
| **Apple App Store Connect Products** | App Store Connect Portal | **`REAL CODE BUT EXTERNAL CONFIGURATION REQUIRED`** | Requires active Apple Developer Program enrollment to register `com.coinscan.plus.monthly`, etc. |
| **RevenueCat Project & Keys** | RevenueCat Dashboard | **`REAL CODE BUT EXTERNAL CONFIGURATION REQUIRED`** | Requires RevenueCat dashboard setup and webhook URL connection. |
| **Google Cloud Run Deployment** | `cloudbuild.yaml`, `backend/Dockerfile` | **`REAL CODE BUT EXTERNAL CONFIGURATION REQUIRED`** | Dockerfile and Cloud Build scripts verified. Live deployment requires running `gcloud builds submit`. |
| **Physical iOS Device IAP Sandbox** | Physical Hardware | **`UNVERIFIED`** | Requires physical iOS device running TestFlight connected to Apple sandbox account. |
| **Secondary Showcase Features** | `lib/core/network/mock_api.dart` | **`MOCK / DEVELOPMENT ONLY`** | Static fixtures used exclusively for marketplace and vault collection previews. Completely isolated from the scan path. |

---

## 3. Discovered Vulnerabilities & Required Fixes in Phase 9

1. **Quota Premature Consumption on Server Error (Step 6):**
   - *Current Code:* In `backend/app/api/recognition.py`, `quota_engine.check_and_consume_quota` is executed at the very beginning of the endpoint request.
   - *Problem:* If image preprocessing fails with an internal server error or the AI provider crashes with 500, the user has already lost one of their daily scans.
   - *Fix:* Refactor quota service into a two-phase check: (1) `check_quota_available` before processing, and (2) `consume_quota` only upon successful evaluation.
2. **DevSubscriptionService Availability in Production (Step 5):**
   - *Current Code:* `DevSubscriptionService` allows simulated instant purchases.
   - *Fix:* Add an environment-aware safety guard so that in `AppEnvironment.production`, if external StoreKit/RevenueCat is not yet initialized, it displays a truthful configuration status rather than pretending a payment succeeded.
3. **Realistic Uncertainty & Accuracy Communication (Step 18 & 19):**
   - *Current Documentation:* Phase 6 mentions 100% benchmark accuracy on 20 internal samples.
   - *Fix:* Clarify in all documentation and UI that numismatic identification from photographs is probabilistic and subject to lighting, wear, and variety nuance.
