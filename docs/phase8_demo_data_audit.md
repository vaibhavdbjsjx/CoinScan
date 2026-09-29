# CoinScan Phase 8: Demo & Fixture Data Audit

**Date:** 2026-08-27  
**Author:** Senior Staff Quality & Systems Engineer  
**Document Version:** 1.0.0  
**Status:** **ACTIVE / VERIFIED**

---

## 1. Executive Summary

This audit catalogs all instances of `MockApi`, demo data, and fixture structures across the CoinScan codebase. It confirms that **the production coin scanning, identification, confidence calculation, valuation, and quota pathways are completely decoupled from demo data and operate strictly on real inputs and backend responses**.

---

## 2. Codebase Audit by Subsystem

### 2.1 Core Production Path (Real & Verified)
| Component | File Path | Status | Verification Detail |
|---|---|---|---|
| **Camera Viewfinder** | `lib/features/scan/scan_screen.dart` | **Real** | Uses Flutter `camera` controller and real hardware lens captures. |
| **Gallery Import** | `lib/features/scan/scan_screen.dart` | **Real** | Uses `image_picker` to load real user photos. |
| **HTTP Recognition Service** | `lib/core/recognition/http_recognition_service.dart` | **Real** | Sends multipart requests to FastAPI backend; parses real responses. |
| **Backend Vision Engine** | `backend/app/services/recognition/vision_provider.py` | **Real** | Connects to Google Gemini (`gemini-2.0-flash`) or OpenAI. |
| **Numismatic Verification** | `backend/app/services/numista/client.py` | **Real** | Queries live Numista v3 API for catalogue confirmation. |
| **Valuation Engine** | `backend/app/services/valuation/valuation_service.py` | **Real** | Computes 4-layer valuation based on metal spot prices and Numista data. |
| **Scan History Persistence** | `lib/core/storage/scan_history_service.dart` | **Real** | Persists real scans to local JSON storage via `path_provider`. |

### 2.2 Secondary UI Showcase & Educational Previews (Fixture Data)
The following screens consume static fixtures in `lib/core/network/mock_api.dart` solely for UI layout rendering:

1. **Marketplace Screen (`lib/features/market/marketplace_screen.dart`):**
   - Displays sample community listings (Marcus Aurelius, Penny Collector LLC) for UI design demonstration.
   - *Status:* Isolated to marketplace tab.
2. **Collection Vault Screen (`lib/features/collection/collection_vault_screen.dart`):**
   - Displays sample portfolio items (Saint-Gaudens, Athenian Owl) to demonstrate portfolio charting and series completion UI.
   - *Status:* Isolated to collection tab.
3. **Profile & Learn Screens (`lib/features/profile/profile_screen.dart`):**
   - Displays educational numismatic lessons ("How to Grade Coins: The Sheldon Scale", "Detecting Counterfeit Gold Coins") and collector achievements.
   - *Status:* Educational content.

---

## 3. Isolation & Production Integrity Guarantees

1. **No Fake Scans in Production:** `MockApi.simulateScan()` is not called anywhere in the active scan route (`/` or `ScanScreen`). If the backend is offline, `HttpRecognitionService` truthfully returns `RecognitionStatus.unavailable` or `RecognitionStatus.error` with actionable diagnostics.
2. **No Fake Subscription Success in Production:** The paywall screen strictly interacts with `SubscriptionService`. In production, when wired to RevenueCat / StoreKit 2, purchases are confirmed only after Apple cryptographic receipt validation.
3. **Truthful Valuation Estimates:** Valuations returned by the backend clearly distinguish bullion melt value from historical collector estimates and display the required numismatic disclaimer.
