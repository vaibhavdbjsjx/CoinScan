# CoinScan Phase 8: App Store Monetization & Review Checklist

**Date:** 2026-08-27  
**Author:** Senior Staff iOS Release & Compliance Engineer  
**Document Version:** 1.0.0  
**Status:** **ACTIVE / VERIFIED**

---

## 1. Compliance Matrix by Status

```
Legend:
[IMPLEMENTED]              -> Built in codebase, verified locally.
[CONFIGURATION REQUIRED]   -> Configuration in code/build settings ready; needs deployment.
[APPLE PORTAL REQUIRED]    -> Requires action in Apple Developer / App Store Connect account.
[REVENUECAT REQUIRED]      -> Requires action in RevenueCat dashboard.
[PHYSICALLY UNVERIFIED]    -> Requires physical iOS device / TestFlight testing.
```

---

## 2. Detailed Item Breakdown

| Item | Requirement & Guideline | Status | Notes / Implementation Location |
|---|---|---|---|
| **In-App Purchase (IAP)** | Guideline 3.1.1: Digital content/services must use StoreKit | **[IMPLEMENTED]** | `lib/core/subscriptions/entitlement_models.dart`, `subscription_service.dart` |
| **IAP Product IDs** | Plus & Pro monthly/yearly products configured | **[APPLE PORTAL REQUIRED]** | Must create in App Store Connect: `com.coinscan.plus.monthly`, `com.coinscan.plus.yearly`, `com.coinscan.pro.monthly`, `com.coinscan.pro.yearly` |
| **Shared Secret / Key** | StoreKit 2 Private Key / App Store Server Notifications v2 | **[APPLE PORTAL REQUIRED]** | Generate in App Store Connect → Users and Access → Keys → In-App Purchase |
| **RevenueCat Project** | App configured with App Store Shared Secret | **[REVENUECAT REQUIRED]** | Create Project in RevenueCat → Connect iOS App + In-App Purchase Key |
| **Restore Purchases** | Guideline 3.1.1: Must provide working Restore Purchases button | **[IMPLEMENTED]** | Implemented on `PaywallScreen` (`_restorePurchases` calls `SubscriptionService.restorePurchases`) |
| **Terms of Service Link**| Guideline 3.1.2: Terms accessible on Paywall & Settings | **[IMPLEMENTED]** | `lib/features/profile/legal_screen.dart`, `docs/terms_of_service.md` |
| **Privacy Policy Link** | Guideline 5.1.1: Privacy policy accessible before/after purchase | **[IMPLEMENTED]** | `lib/features/profile/legal_screen.dart`, `docs/privacy_policy.md` |
| **Auto-Renewal Terms** | Clear explanation that subscription renews unless cancelled 24h prior | **[IMPLEMENTED]** | Displayed in Paywall footer text and LegalScreen |
| **Valuation Disclaimer** | Disclaimer stating valuations are numismatic estimates, not appraisals | **[IMPLEMENTED]** | Included in Terms of Service section 2 and Result screens |
| **Zero Image Retention**| Clear disclosure that images are processed in-memory and discarded | **[IMPLEMENTED]** | Included in Privacy Policy section 2 |
| **Account Deletion** | Guideline 5.1.1(v): In-app account deletion mechanism | **[IMPLEMENTED]** | Database cascading delete triggers on `auth.users(id)` and RLS policies |
| **Camera/Photo Permissions**| `NSCameraUsageDescription` & `NSPhotoLibraryUsageDescription` | **[IMPLEMENTED]** | Configured in `ios/Runner/Info.plist` |
| **Physical IAP Sandbox Test**| StoreKit Sandbox test with test Apple ID | **[PHYSICALLY UNVERIFIED]** | Blocked on physical iPhone and Apple Developer Account setup |

---

## 3. Pre-Submission Step-by-Step Guide

1. **Step 1:** Log into [App Store Connect](https://appstoreconnect.apple.com).
2. **Step 2:** Under **Subscriptions**, create a Subscription Group named `"CoinScan Premium"`.
3. **Step 3:** Add 4 Auto-Renewable Subscription Products:
   - `com.coinscan.plus.monthly` ($4.99)
   - `com.coinscan.plus.yearly` ($39.99)
   - `com.coinscan.pro.monthly` ($9.99)
   - `com.coinscan.pro.yearly` ($79.99)
4. **Step 4:** Set App Store Server Notifications URL to `https://api.coinscan.app/v1/webhooks/revenuecat` (or RevenueCat webhook proxy).
5. **Step 5:** Upload App Store screenshots highlighting coin identification and valuation features with visible disclaimer text.
