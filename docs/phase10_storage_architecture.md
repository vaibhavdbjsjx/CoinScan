# CoinScan Phase 10: Four-Tier Storage & Cloud Object Architecture

**Date:** 2026-08-29  
**Author:** Principal Platform & Infrastructure Architect  
**Document Version:** 1.0.0  
**Status:** **ACTIVE / VERIFIED**

---

## 1. The Four-Tier Storage Model

```
+---------------------------------------------------------------------------------------------------+
|                                  COINSCAN FOUR-TIER STORAGE MODEL                                 |
+---------------------------------------------------------------------------------------------------+

1. EPHEMERAL RECOGNITION IMAGES (Server In-Memory)
   Camera/Gallery ──► Multipart Upload ──► Fast In-Memory Normalization ──► AI Analysis ──► Discarded
   • Lifetime: Request processing duration only (< 3 seconds)
   • Storage: RAM / temporary buffer (NEVER written to persistent server disk)
   • Zero server retention policy strictly adhered to

2. LOCAL DEVICE STORAGE (Sandboxed App Documents)
   • Scan history JSON & thumbnail cache
   • User preferences (preferred currency, unit formatting, theme)
   • Offline collection metadata
   • Handled via `path_provider` sandboxed directory

3. SECURE DEVICE STORAGE (iOS Keychain / Android Keystore)
   • Authentication JWT bearer tokens & refresh tokens
   • Active session identifiers
   • Biometric lock preferences & client security flags
   • Handled via `SecureStorageService` abstraction

4. CLOUD DATABASE & OBJECT STORAGE (Supabase PostgreSQL & Private GCS/S3)
   • Relational data: User profiles, subscriptions, entitlements, scan quotas, API keys
   • Object storage: Private user vault images (ONLY when explicitly saved to collection)
   • Access: Private buckets with time-limited HMAC-signed URLs and RLS ownership validation
```

---

## 2. Ephemeral Recognition Lifecycle

1. **Capture & Transport:** Mobile client captures front, reverse, and optional edge images, encoding them into multipart form-data over TLS 1.3.
2. **Server Ingestion:** FastAPI receives `UploadFile` streams into memory.
3. **Preprocessing:** PIL inspects sharpness (Laplacian variance) and normalizes dimensions (max 1024px).
4. **Provider Inference:** Base64 payload forwarded to Google Gemini or OpenAI vision models under enterprise zero-data-retention agreements.
5. **Immediate Cleanup:** After evidence aggregation and response serialization, in-memory buffers are garbage collected. No server-side logging or disk persistence of user photos occurs.

---

## 3. Persistent Collection Vault Storage

When a user explicitly taps **"Add to Vault / Save Collection"**:
- **Local Persistence:** Coin metadata and local photo reference are saved to `CollectionStorageService` (in-app documents directory).
- **Cloud Synchronization:**
  - Structured metadata is inserted into `public.collection_items` in PostgreSQL.
  - Image is uploaded to a private bucket (`coinscan-user-vaults/{user_id}/{item_id}.jpg`).
  - Strict file-size limit: 10 MB maximum.
  - Allowed MIME types: `image/jpeg`, `image/png`, `image/webp`.
  - Object access: Accessible only via short-lived signed URLs (15-minute expiration) generated after verifying `auth.uid() = user_id`.

---

## 4. Local Database Assessment (JSON vs SQLite vs Drift)

- **Current Implementation:** JSON file-based persistence via `path_provider`.
- **Evaluation:**
  - For typical user portfolios (< 500 coins), atomic JSON file writes with in-memory caching offer high performance, zero external native compilation dependencies, and bulletproof iOS/Android/Web compatibility.
  - Corrupted files are gracefully recovered via `.bak` fallback snapshots and schema migration checks.
  - Migration to SQLite/Drift remains an option for future high-volume dealer catalogues (> 5,000 items).
- **Decision:** Maintain clean, robust JSON document persistence with atomic write-rename guarantees and in-memory indexes.
