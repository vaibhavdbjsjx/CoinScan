# CoinScan Phase 10: Authentication, Identity & Session Security

**Date:** 2026-08-29  
**Author:** Principal Identity & Security Architect  
**Document Version:** 1.0.0  
**Status:** **ACTIVE / VERIFIED**

---

## 1. Authentication Architecture Overview

CoinScan supports a hybrid identity architecture designed for seamless onboarding without sacrificing enterprise security:

```
+---------------------------------------------------------------------------------------------------+
|                                  COINSCAN AUTHENTICATION PIPELINE                                 |
+---------------------------------------------------------------------------------------------------+

                          +-----------------------------+
                          |      Unauthenticated /      |
                          |         Guest State         |
                          +--------------+--------------+
                                         |
                                         | (User chooses sign in or upgrade)
                                         v
                         +---------------+---------------+
                         |   Identity Provider Select   |
                         +---------------+---------------+
                                         |
                +------------------------+------------------------+
                |                                                 |
                v                                                 v
  +---------------------------+                     +---------------------------+
  |    Sign in with Apple     |                     |    Email Magic / OAuth    |
  | (Native iOS Private Relay)|                     |     (Supabase Auth)       |
  +-------------+-------------+                     +-------------+-------------+
                |                                                 |
                +------------------------+------------------------+
                                         |
                                         v
                      +-----------------------------------+
                      |      Cryptographic JWT Issue      |
                      |  (Signed RS256/HS256 server token)|
                      +------------------+----------------+
                                         |
                                         v
                      +-----------------------------------+
                      |   Client Secure Keychain Store    |
                      |     (`SecureStorageService`)      |
                      +------------------+----------------+
                                         |
                                         v
                      +-----------------------------------+
                      |   FastAPI Authoritative Context   |
                      |   (`get_current_user` in auth.py) |
                      +-----------------------------------+
```

---

## 2. Token Storage & Session Security

1. **Client-Side Keychain:** All session JWTs are stored in hardware-backed secure storage (iOS Keychain and Android Keystore) via `SecureStorageService`.
2. **Zero Insecure LocalStorage:** Secrets and session bearer tokens are never written to plain `SharedPreferences` or browser `localStorage` in production.
3. **Automatic Expiration & Refresh:** JWT access tokens expire after 3600 seconds (1 hour); refresh tokens are rotated on each exchange.
4. **Authoritative Server Context:** Client claims of subscription tiers (`X-Tier: pro`) are strictly rejected by `UnifiedAuthenticator` unless backed by a cryptographically signed JWT token or valid hashed API key.

---

## 3. Supported Authentication States

- **Guest State (`isAnonymous: true`):** Allows immediate camera scanning and evaluation within free daily quota limits without forcing upfront account creation.
- **Authenticated Collector (`isAnonymous: false`):** Enables persistent cloud collection vaults, multi-device portfolio sync, and Plus/Pro quota expansions.
