# CoinScan Phase 7: Production Product Architecture & Monetization Stack

**Date:** 2026-08-26  
**Document Version:** 1.0.0  
**Status:** **ACTIVE / VERIFIED**

---

## 1. System Architecture Overview

```
+-------------------------------------------------------------------------------+
|                                FLUTTER CLIENT                                 |
|                                                                               |
|  +---------------------+   +---------------------+   +---------------------+  |
|  |     Scan Screen     |   |   Paywall Screen    |   | Scan History Screen |  |
|  | (Camera & Gallery)  |   | (Plus / Pro Tiers)  |   | (Local Persistence) |  |
|  +----------+----------+   +----------+----------+   +----------+----------+  |
|             |                         |                         |             |
|             v                         v                         v             |
|  +---------------------+   +---------------------+   +---------------------+  |
|  |  HttpRecognition-   |   | SubscriptionService |   | ScanHistoryService  |  |
|  |      Service        |   | (StoreKit / Dev)    |   |    (JSON / DB)      |  |
|  +----------+----------+   +---------------------+   +---------------------+  |
|             |                                                                 |
|             v                                                                 |
|     AppConfig Layer (Environment, Base URL, API Key via --dart-define)        |
+-------------+-----------------------------------------------------------------+
              |
              | HTTPS (multipart/form-data + X-API-Key)
              v
+-------------------------------------------------------------------------------+
|                             COINSCAN FASTAPI BACKEND                          |
|                                (Google Cloud Run)                             |
|                                                                               |
|  +-------------------------------------------------------------------------+  |
|  | Security & Auth Middleware (auth.py, rate_limit.py)                    |  |
|  | - API Key verification & Subscription tier resolution                   |  |
|  | - IP sliding-window throttling & Tier-based quota enforcement            |  |
|  +------------------------------------+------------------------------------+  |
|                                       |                                       |
|                                       v                                       |
|  +-------------------------------------------------------------------------+  |
|  | Image Quality & Normalization (inspect_image_quality, Laplacian blur)   |  |
|  +------------------------------------+------------------------------------+  |
|                                       |                                       |
|                   +-------------------+-------------------+                   |
|                   |                                       |                   |
|                   v                                       v                   |
|  +---------------------------------+   +-----------------------------------+  |
|  | Multimodal Vision AI Provider   |   | OCR Numismatic Signal Extractor   |  |
|  | (Gemini 2.0 Flash / GPT-4o-mini)|   | (Gregorian year, denomination, MM)|  |
|  +----------------+----------------+   +------------------+----------------+  |
|                   |                                       |                   |
|                   +-------------------+-------------------+                   |
|                                       |                                       |
|                                       v                                       |
|  +-------------------------------------------------------------------------+  |
|  | Evidence Aggregation Engine (evidence_engine.py)                        |  |
|  | - Two-sided die consistency & contradiction detection                   |  |
|  | - Numista v3 Catalogue Verification (API key proxy / attribution)       |  |
|  +------------------------------------+------------------------------------+  |
|                                       |                                       |
|                                       v                                       |
|  +-------------------------------------------------------------------------+  |
|  | Valuation Engine (valuation_service.py, metal_price_provider.py)        |  |
|  | - Layer 1: Face value | Layer 2: Intrinsic fine bullion melt value        |  |
|  | - Layer 3: Numismatic collector estimate | Layer 4: Realized auctions   |  |
|  | - FX localized pricing (fx_service.py cached with TTL)                  |  |
|  +-------------------------------------------------------------------------+  |
+-------------------------------------------------------------------------------+
```

---

## 2. Monetization & Entitlement Architecture

### 2.1 Product Tiers & Quotas
| Tier | Price | Daily Scan Quota | Advanced Recognition | Market Valuation | History & Export |
|---|---|---|---|---|---|
| **Limited (Free)** | $0.00 | 3 scans / day | Baseline | ❌ | ❌ |
| **Plus (Monthly)** | $4.99 / mo | 30 scans / day | Full Multi-signal | ❌ | ✅ |
| **Plus (Yearly)** | $39.99 / yr | 30 scans / day | Full Multi-signal | ❌ | ✅ |
| **Pro (Monthly)** | $9.99 / mo | Unlimited (∞) | Full Multi-signal | ✅ | ✅ |
| **Pro (Yearly)** | $79.99 / yr | Unlimited (∞) | Full Multi-signal | ✅ | ✅ |

### 2.2 Client-Side Quota Enforcement Flow
1. User captures coin front + reverse (+ optional edge).
2. Tapping "Analyze" queries `SubscriptionService.currentEntitlement()`.
3. If `canScan == false` (quota reached):
   - Navigation pushes `PaywallScreen`.
   - User selects Plan or taps "Restore Purchases".
   - If purchase succeeds, scan proceeds; otherwise remains on review screen.
4. If `canScan == true`:
   - `HttpRecognitionService.recognize(input)` executes.
   - `SubscriptionService.recordScanUsage()` tracks quota consumption.
   - Result is saved to `ScanHistoryService`.

---

## 3. Security & Secrets Isolation

1. **Client Isolation:** Zero third-party API keys (Gemini, OpenAI, Numista, Metals-API, ExchangeRate-API) exist in Flutter code or client assets.
2. **Backend Authentication:**
   - Optional `X-API-Key` header passed from mobile client.
   - `auth.py` validates against server configuration (`API_KEYS_JSON` or database).
   - Rate limiter dynamically adjusts limits per tier (Anonymous: 60 rpm IP throttle; Pro: 120 rpm).
3. **Deployment Security:**
   - Dockerfile runs as unprivileged non-root user `coinscan`.
   - Cloud Build deploys to Google Cloud Run injecting secrets from Google Secret Manager (`--set-secrets`).

---

## 4. Production Deployment & Cloud Build Specification

- **Target:** Google Cloud Run (Serverless Container Platform)
- **Container Registry:** Google Artifact Registry (`us-central1-docker.pkg.dev/$PROJECT_ID/coinscan/coinscan-backend`)
- **Automated CI/CD:** `cloudbuild.yaml` with build, push, and deploy steps.
- **Health Check:** Container `HEALTHCHECK` probe and `/health` route.
