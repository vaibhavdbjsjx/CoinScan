# CoinScan Phase 10: Security, Storage, Authentication, Privacy & Support Audit

**Date:** 2026-08-29  
**Author:** Principal Platform, Security & Mobile Systems Architect  
**Document Version:** 1.0.0  
**Status:** **AUDIT VERIFIED**

---

## 1. Executive Summary

Phase 10 addresses the full lifecycle of client-side and server-side data management, authentication states, user privacy controls, account deletion, support/feedback infrastructure, and security guarantees.

This audit reviews every relevant subsystem and classifies each according to its exact implementation state.

---

## 2. Subsystem Classification Matrix

| Subsystem / Area | Component | Classification | Finding & Architectural Analysis |
|---|---|---|---|
| **Local Device Storage** | `scan_history_service.dart` | **`REAL`** | Uses `path_provider` to persist `ScanRecord` JSON arrays. Safe fallback on web. |
| **Secure Device Storage** | Keychain / Token Store | **`MISSING`** | Currently auth tokens are in-memory. Requires dedicated `SecureStorageService` abstraction. |
| **Collection Storage** | Vault / Collection Items | **`PARTIALLY REAL`** | `MockApi.getPortfolioItems()` was used in UI previews. Needs persistent `CollectionStorageService`. |
| **Ephemeral Recognition** | Backend Image Uploads | **`REAL`** | Images are processed in-memory via `UploadFile`, converted to PIL/bytes, and never written to permanent disk blobs. |
| **Cloud Object Storage** | Private User Image Buckets | **`EXTERNAL CONFIGURATION REQUIRED`** | S3/GCS bucket architecture documented; no images stored permanently unless user explicitly saves to collection. |
| **Authentication Core** | `auth.py`, `jwt_auth.py` | **`REAL`** | Server-authoritative JWT verification, API key SHA-256 validation, and rejection of spoofed client `X-Tier` claims. |
| **Account Management** | `profile_screen.dart` | **`PARTIALLY REAL`** | Profile UI rendered collector metrics; needs dedicated `AccountSettingsScreen` with progressive disclosure. |
| **Account Deletion** | Deletion Workflow & Endpoint | **`MISSING`** | Needs `POST /v1/account/delete` backend endpoint, cascading DB delete trigger, and Flutter confirmation UI. |
| **Data Export** | Data Portability (JSON/CSV) | **`MISSING`** | Needs export engine for scan history and collection items excluding tokens/secrets. |
| **Help & Support** | In-App Help Center | **`MISSING`** | Needs dedicated in-app Help Center with FAQs on two-sided die capture, valuation disclaimers, and camera tips. |
| **Feedback System** | Feedback & Bug Reporting | **`MISSING`** | Needs `POST /v1/feedback` endpoint with rate-limiting, category validation, and Flutter feedback UI. |
| **App Lock / Biometrics** | Local Biometric Privacy | **`REAL (PLANNED / DEFERRED)`** | Evaluated as a local client-side option. No backend authentication claims made. |
| **Privacy & Legal** | `legal_screen.dart`, policies | **`REAL`** | In-app legal viewer with Privacy Policy and Terms of Service. |
| **Capacitor Integration**| Web-to-Native Wrapper | **`NOT USED`** | Confirmed: Zero Capacitor in codebase. Pure native Flutter on iOS & Android. |

---

## 3. Action Plan for Phase 10 Implementation

1. **Storage Layer:** Build `SecureStorageService` and `CollectionStorageService` (supporting current vs historical valuation snapshots).
2. **Authentication & Session:** Build `AuthService` handling guest modes, session restoration, logout, and token security.
3. **Backend Endpoints:**
   - `POST /v1/feedback`: Validated, rate-limited user feedback and bug reporting.
   - `POST /v1/account/delete`: Cascading account data deletion.
   - `GET /v1/account/export`: Safe data export.
   - `POST /v1/collection` & `GET /v1/collection`: User collection management with IDOR ownership validation.
4. **UI Sections:**
   - In-app Help Center (`HelpCenterScreen`).
   - Feedback & Bug Report modal (`FeedbackScreen`).
   - Account Settings & Data Management (`AccountSettingsScreen`, `DataManagementScreen`).
5. **Documentation & Validation:** Create comprehensive Phase 10 documentation and unit tests.
