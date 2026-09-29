# CoinScan Phase 14.5: Production Credential & Account Discovery Report

**Date:** 2026-08-30  
**Author:** Principal Infrastructure, Security & Mobile Architect  
**Document Version:** 1.0.0  
**Status:** **DISCOVERY COMPLETED (NO CODE CHANGES)**

---

## 1. Executive Summary

This discovery audit investigates the exact local tools, cloud accounts, credentials, CLIs, simulator runtimes, and external domain mappings currently present on this development Mac.

No cloud resources were created, no code changes were made, and no secrets were exposed.

---

## 2. Comprehensive Account & Credential Discovery Summary

| Component / Subsystem | Current State | Evidence & Discovery Detail |
|---|---|---|
| **Google Cloud (GCP)** | **`NOT CONFIGURED`** | `gcloud` CLI is not installed in PATH; no `~/.config/gcloud` directory exists. No active GCP project is bound locally. |
| **Supabase** | **`NOT CONFIGURED`** | `supabase` CLI is not installed; no `~/.supabase` directory exists. `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are absent from environment. |
| **Google Gemini Vision AI** | **`ABSENT`** | `GEMINI_API_KEY` is absent from environment variables. |
| **Numista Commercial API** | **`ABSENT`** | `NUMISTA_API_KEY` is absent from environment variables. |
| **RevenueCat** | **`NOT CONFIGURED`** | Product IDs and webhook receiver are implemented in code; external RevenueCat project dashboard connection not established. |
| **Domain Resolution** | **`NOT RESOLVING`** | `coinscan.app` and `api.coinscan.app` resolve to AWS parking IP addresses (`13.248.169.48`, `76.223.54.146`); HTTP/HTTPS requests time out (no active backend listener). |
| **Cloud Run Service** | **`NOT AVAILABLE`** | Cannot deploy from local machine until `gcloud` is installed and authenticated. |
| **Google Secret Manager** | **`NOT AVAILABLE`** | Cannot configure or query until GCP authentication is established. |
| **iOS Simulator** | **`BLOCKED`** | Xcode 26.6 is installed, but `xcrun simctl list runtimes` contains 0 platform runtimes (iOS SDK simulator component is not downloaded). |
| **Physical iPhone Device** | **`BLOCKED`** | `security find-identity -v -p codesigning` reports `0 valid identities found`. No physical device is attached. |
| **JWT Verification Mechanism** | **`JWKS / RS256 (RECOMMENDED)`** | Modern Supabase projects use asymmetric RS256/ES256 signatures validated against `https://<project-ref>.supabase.co/auth/v1/.well-known/jwks.json`. Legacy fallback supports HS256 with `SUPABASE_JWT_SECRET`. |

---

## 3. Local Tooling Matrix

| Tool | Installed | Version / Path |
|---|---|---|
| **Flutter** | **YES** | `Flutter 3.44.4 (stable)` (`/Users/vaibhavsg/development/flutter/bin/flutter`) |
| **Dart** | **YES** | `Dart SDK 3.12.2 (stable)` |
| **Xcode / xcodebuild** | **YES** | `Xcode 26.6 (Build 17F113)` |
| **xcrun** | **YES** | `xcrun version 72` |
| **gcloud** | **NO** | Not found in PATH |
| **docker** | **NO** | Not found in PATH |
| **supabase** | **NO** | Not found in PATH |

---

## 4. Environment Variables Audit

- `GEMINI_API_KEY`: **ABSENT**
- `NUMISTA_API_KEY`: **ABSENT**
- `SUPABASE_URL`: **ABSENT**
- `SUPABASE_SERVICE_ROLE_KEY`: **ABSENT**
- `REVENUECAT_WEBHOOK_SECRET`: **ABSENT**
- `SUPABASE_JWT_SECRET`: **ABSENT**
- `EXCHANGERATE_API_KEY`: **ABSENT**
- `OPENAI_API_KEY`: **ABSENT**

---

## 5. What Must Be Done to Go Live

1. **Supabase Setup:**
   - Create a project on [supabase.com](https://supabase.com).
   - Execute the canonical database migration script ([20260830_phase11_production_schema.sql](file:///Users/vaibhavsg/Documents/coinscan/backend/migrations/20260830_phase11_production_schema.sql)) via the Supabase SQL Editor.
   - Obtain the project URL, anon key, and service-role key.
2. **Google Cloud Platform (GCP) Setup:**
   - Install the Google Cloud SDK (`brew install google-cloud-sdk` or download installer).
   - Authenticate with `gcloud auth login` and set the target project (`gcloud config set project <PROJECT_ID>`).
   - Store production secrets in Secret Manager (`GEMINI_API_KEY`, `NUMISTA_API_KEY`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `REVENUECAT_WEBHOOK_SECRET`).
   - Deploy backend container to Google Cloud Run via `gcloud builds submit --config=cloudbuild.yaml`.
3. **DNS / Custom Domain Mapping:**
   - Map `api.coinscan.app` to the Cloud Run service in GCP Custom Domains.
   - Update DNS CNAME / A records in the domain registrar.
4. **Apple Developer & TestFlight Setup:**
   - Download iOS Simulator component in Xcode (`Xcode > Settings > Components > iOS Simulator`).
   - Add Apple Developer account in `Xcode > Settings > Accounts` for code signing.
