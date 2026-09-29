# CoinScan Phase 10: Privacy, Security Controls & Worldwide Localization

**Date:** 2026-08-29  
**Author:** Principal Security & Localization Architect  
**Document Version:** 1.0.0  
**Status:** **ACTIVE / VERIFIED**

---

## 1. Security Architecture & Threat Mitigations

| Threat Vector | Mitigation Strategy | Implementation Location |
|---|---|---|
| **Insecure Direct Object Reference (IDOR)** | All collection mutations require authenticated `user_id` context. SQL queries enforce `WHERE user_id = auth.uid()`. Cross-user access returns `404 Not Found`. | `backend/app/api/collection.py` |
| **Quota Circumvention & Race Attacks** | Atomic `asyncio.Lock` check-and-increment on daily scan consumption counters. UTC boundary resets. | `backend/app/security/quota_service.py` |
| **API Abuse & Feedback Spam** | Tier-aware token bucket rate limiter for scanning; sliding-window rate limit (max 5 requests/10 min) on feedback submissions. | `backend/app/security/rate_limit.py`, `feedback.py` |
| **Credential & Secret Exposure** | Cryptographic SHA-256 key storage; zero raw token persistence in client logs or crash reports. Hardware Keychain storage. | `backend/app/security/api_key_service.py`, `secure_storage_service.dart` |
| **Client Tier Spoofing** | Discard client-asserted `X-Tier` headers; derive tier solely from verified JWT or API key record. | `backend/app/security/auth.py` |

---

## 2. Image Privacy & Ephemeral Data Lifecycle

- **Recognition Processing:** Images uploaded during active scanning are held strictly in temporary RAM buffers for Laplacian variance calculation, dimension normalization, and inference. They are never written to disk or used for model training.
- **Permanent Storage:** Cloud object storage is only activated when a user explicitly taps **"Add to Vault"**. Images are placed in user-isolated private buckets accessible exclusively via short-lived HMAC-signed URLs.

---

## 3. Worldwide Localization & Currency Standards

- **No Regional Bias:** The application avoids hardcoding single-country assumptions (e.g. INR-only, USD-only, or US-centric dates).
- **Locale-Aware Formatting:** Currency codes (`USD`, `EUR`, `GBP`, `CAD`, `AUD`, `JPY`, `INR`) and number formatting dynamically format according to the user's selected locale using the `intl` package.
- **Standardized UTC Epochs:** All scan timestamps and quota resets are calculated relative to UTC `00:00:00` to prevent timezone-exploitation attacks.
