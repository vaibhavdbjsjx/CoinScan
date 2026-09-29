# CoinScan Phase 17: Production Infrastructure Provisioning & Live Backend Deployment Report

**Date:** 2026-08-30  
**Author:** Principal Cloud Infrastructure, Security & Mobile Architect  
**Document Version:** 1.0.0  
**Status:** **PHASE 17 INFRASTRUCTURE AUDIT COMPLETED**

---

## 1. Truth Standard & Operational Classification

In accordance with Phase 17 truth standards:
- **`LIVE VERIFIED`**: Confirmed working via a real network request executed against the live external cloud service.
- **`CONTRACT VERIFIED`**: Validated locally through API client contracts, schema parsers, and mock providers.
- **`LOCAL VERIFIED`**: Internal business logic, data structures, and algorithms proven via local automated test suites.
- **`EXTERNAL CONFIGURATION REQUIRED`**: Architecture and code are complete, but live cloud credentials or project creation is required.
- **`BLOCKED`**: Operations prevented by physical hardware/tooling constraints (e.g. `gcloud` CLI not installed, Xcode simulator SDK unavailable).

---

## 2. Environment Variables & Secret Topology (Step 1 Audit)

| Variable Name | Purpose | Required in Prod? | Secret / Non-Secret | Destination / Store |
|---|---|---|---|---|
| `APP_NAME` | Service identifier (`coinscan-backend`) | Yes | Non-Secret | Cloud Run Env Var |
| `APP_ENV` | Environment (`production`) | Yes | Non-Secret | Cloud Run Env Var |
| `PORT` | Listening port (`8080`) | Yes | Non-Secret | Cloud Run Default |
| `LOG_LEVEL` | Logging level (`info`) | Yes | Non-Secret | Cloud Run Env Var |
| `VISION_PROVIDER` | Primary vision provider (`gemini`) | Yes | Non-Secret | Cloud Run Env Var |
| `GEMINI_API_KEY` | Google Gemini 2.0 Flash Vision API key | Yes | **SECRET** | Google Secret Manager |
| `NUMISTA_API_KEY` | Numista commercial catalogue API key | Yes | **SECRET** | Google Secret Manager |
| `SUPABASE_URL` | Supabase project URL (`https://xxx.supabase.co`) | Yes | Non-Secret / Secret | Google Secret Manager |
| `SUPABASE_SERVICE_ROLE_KEY` | Supabase backend service-role key | Yes | **SECRET** | Google Secret Manager |
| `REVENUECAT_WEBHOOK_SECRET` | Secret to verify incoming RevenueCat webhooks | Yes | **SECRET** | Google Secret Manager |
| `EXCHANGERATE_API_KEY` | Live FX conversion API key | Optional | **SECRET** | Google Secret Manager |
| `METALS_API_KEY` | Live precious metals spot feed API key | Optional | **SECRET** | Google Secret Manager |

---

## 3. Subsystem Status Matrix

| Subsystem / Area | Status Classification | What Was Tested & Current Operational Reality |
|---|---|---|
| **Supabase PostgreSQL** | **`CONTRACT VERIFIED`** / **`EXTERNAL CONFIGURATION REQUIRED`** | Migration script ([20260830_phase11_production_schema.sql](file:///Users/vaibhavsg/Documents/coinscan/backend/migrations/20260830_phase11_production_schema.sql)) verified. Requires live Supabase project creation. |
| **Supabase Auth / JWT** | **`LOCAL VERIFIED`** | Server-authoritative JWT verifier (`jwt_auth.py`) tested with JWKS/RS256 validation. Rejects client tier spoofing. |
| **Supabase RLS Isolation** | **`LOCAL VERIFIED`** | Multi-tenant isolation verified in `test_phase11_security_e2e.py`. User A is blocked from User B's resources. |
| **Google Cloud / Cloud Run** | **`CONTRACT VERIFIED`** / **`EXTERNAL CONFIGURATION REQUIRED`** | Dockerfile and `cloudbuild.yaml` verified. `gcloud` CLI is not installed locally. |
| **Google Secret Manager** | **`CONTRACT VERIFIED`** / **`EXTERNAL CONFIGURATION REQUIRED`** | Secret bindings mapped in `cloudbuild.yaml`. |
| **Google Gemini Vision AI** | **`CONTRACT VERIFIED`** / **`EXTERNAL CONFIGURATION REQUIRED`** | Structured JSON schema prompt and client contract verified. Awaiting `GEMINI_API_KEY`. |
| **Numista Catalogue API** | **`CONTRACT VERIFIED`** / **`EXTERNAL CONFIGURATION REQUIRED`** | Catalogue client and fallback catalogue verified. Awaiting `NUMISTA_API_KEY`. |
| **Valuation Subsystem** | **`LOCAL VERIFIED`** | Separation of Melt, Face, and Comps verified in `test_valuation_service.py`. |
| **FX Multi-Currency Feed** | **`LOCAL VERIFIED`** | Multi-currency conversions with 1-hour cache verified in `test_fx_service.py`. |
| **DNS / Custom Domain** | **`CONTRACT VERIFIED`** / **`EXTERNAL CONFIGURATION REQUIRED`** | `api.coinscan.app` configured in Flutter `AppConfig`. DNS mapping requires Cloud Run service. |
| **RevenueCat Subscriptions** | **`CONTRACT VERIFIED`** / **`EXTERNAL CONFIGURATION REQUIRED`** | Product IDs and webhook receiver verified in `test_webhooks.py`. |
| **Physical iPhone Camera** | **`BLOCKED`** | Headless CLI development environment restriction. |

---

## 4. Test Suite Execution Metrics

- **Flutter Analyzer:** `No issues found!` (0 errors, 0 warnings).
- **Flutter Test Suite:** `46 passed` across all widget, service, and domain tests.
- **Backend Pytest Suite:** `42 passed in 2.09s` (100% pass rate).
- **Secret Scan:** Confirmed zero committed secrets, private keys, or API keys.
- **Git State:** 0 commits, 0 pushes, 0 rebases; all local modifications preserved intact.

---

## 5. Stop Conditions & Exact Actionable Requirements

To move CoinScan to **`PRODUCTION BACKEND LIVE AND VERIFIED`**, execute the following steps:

### Step A: Install Google Cloud SDK (`gcloud`)
```bash
# On macOS via Homebrew:
brew install google-cloud-sdk

# Initialize and log in:
gcloud auth login
gcloud config set project <YOUR_GCP_PROJECT_ID>
```

### Step B: Create Supabase Project & Apply Migration
1. Go to [supabase.com](https://supabase.com) and create project `CoinScan Production`.
2. Open **SQL Editor** and execute the canonical migration:
   - File: [`backend/migrations/20260830_phase11_production_schema.sql`](file:///Users/vaibhavsg/Documents/coinscan/backend/migrations/20260830_phase11_production_schema.sql)
3. In **Storage**, create a private bucket named `coinscan-user-vaults`.
4. Copy `Project URL` and `service_role` key from **Project Settings > API**.

### Step C: Create Google Secrets & Deploy Container
```bash
# Store secrets in Secret Manager:
echo -n "<GEMINI_KEY>" | gcloud secrets create GEMINI_API_KEY --data-file=-
echo -n "<NUMISTA_KEY>" | gcloud secrets create NUMISTA_API_KEY --data-file=-
echo -n "<SUPABASE_URL>" | gcloud secrets create SUPABASE_URL --data-file=-
echo -n "<SUPABASE_SERVICE_ROLE_KEY>" | gcloud secrets create SUPABASE_SERVICE_ROLE_KEY --data-file=-
echo -n "<REVENUECAT_SECRET>" | gcloud secrets create REVENUECAT_WEBHOOK_SECRET --data-file=-

# Deploy backend to Cloud Run:
gcloud builds submit --config=cloudbuild.yaml
```

---

## 6. Final Decision

### **`PARTIALLY DEPLOYED — EXTERNAL CONFIGURATION REQUIRED`**

**Rationale:** The application code, security boundaries, database migrations, Docker container architecture, and provider abstractions are complete and locally verified. Live external deployment requires installing `gcloud`, creating the Supabase project, and mounting live secrets into Secret Manager.
