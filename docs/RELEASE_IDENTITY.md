# CoinScan Production Release Identity Specification

This document establishes the single authoritative reference for all application, bundle, package, and store identifiers used across CoinScan.

---

## 1. Authoritative Identity Matrix

| Identity Field | Value | Primary Source | Scope & Usage |
|---|---|---|---|
| **Visible App Display Name** | `CoinScan` | `AndroidManifest.xml`, `Info.plist`, UI Headers | End-user facing brand on homescreen, app title bar, App Store / Google Play listings. |
| **iOS Bundle Identifier** | `com.coinvault.coinvaultAi` | `ios/Runner.xcodeproj/project.pbxproj` | Apple App Store Connect app bundle ID, Provisioning profiles, Push Certificates, Keychains. |
| **Android Application ID** | `com.coinvault.coinvault_ai` | `android/app/build.gradle.kts` | Google Play Console package name, Google Play Billing, Android APK/AAB manifest namespace. |
| **Dart Package Name** | `coinvault_ai` | `pubspec.yaml` | Internal Dart module namespace (`package:coinvault_ai/...`), test imports, plugin registrations. |
| **RevenueCat Apple App ID** | `com.coinvault.coinvaultAi` | RevenueCat Dashboard → iOS App | Must match the iOS bundle ID exactly. |
| **RevenueCat Google Play App ID** | `com.coinvault.coinvault_ai` | RevenueCat Dashboard → Android App | Must match the Android package name exactly. |

---

## 2. In-App Purchase & Subscription Identifiers

The auto-renewable subscription product identifiers in code are canonical and must match App Store Connect and Google Play Console:

| Product Identifier | Billing Recurrence | Plan Tier | Canonical Entitlement ID |
|---|---|---|---|
| `com.coinscan.plus.monthly` | Monthly ($4.99) | Plus | `plus` |
| `com.coinscan.plus.yearly` | Annual ($39.99) | Plus | `plus` |
| `com.coinscan.pro.monthly` | Monthly ($9.99) | Pro | `pro` |
| `com.coinscan.pro.yearly` | Annual ($79.99) | Pro | `pro` |

### Why Product IDs Do NOT Require Renaming
* **App Store Connect**: Apple allows any unique ASCII alphanumeric string (up to 255 characters) for In-App Purchase Product IDs. Apple **does not require** the product ID to start with the app's bundle identifier prefix.
* **Google Play Console**: Google Play subscriptions are identified by a unique alphanumeric ID string scoped to the application. Google **does not require** the subscription ID to match the application ID prefix.
* **RevenueCat**: RevenueCat functions as an abstraction layer. It maps whatever product identifier string is configured in App Store Connect or Google Play Console to the RevenueCat Entitlements (`plus` and `pro`).
* **Stability Guarantee**: Changing `com.coinscan.plus.monthly` to `com.coinvault.coinvault_ai.plus.monthly` would require coordinated changes across Flutter models, test suites, backend webhooks, and database enum mappings without providing any technical benefit. **Do not rename product IDs.**

---

## 3. Impact Analysis: What Would Break If Bundle IDs Are Changed?

Changing `com.coinvault.coinvaultAi` (iOS) or `com.coinvault.coinvault_ai` (Android) at this stage would have catastrophic effects across 8 distinct integration points:

1. **Supabase Auth & OAuth Redirects**:
   * Google & Apple OAuth redirect URLs are registered against custom scheme and bundle IDs (e.g., `com.coinvault.coinvaultai://login-callback`).
   * A bundle ID change invalidates registered client IDs in Google Cloud Console and Apple Developer Sign in with Apple service IDs.
2. **Apple Developer & Provisioning**:
   * App Store Connect app records cannot change their bundle ID after creation.
   * Associated Capabilities (Sign In with Apple, In-App Purchase, Keychain Sharing) are tied to App ID `com.coinvault.coinvaultAi`.
3. **Google Play Console**:
   * Google Play package names are globally permanent once an AAB is uploaded.
4. **RevenueCat App Links**:
   * Receipt validation for StoreKit and Google Play Billing relies on the registered bundle ID / package name matching the incoming receipt payload.
5. **Android Keystore & Release Signing**:
   * Upload keystores are generated with organizational aliases mapped to the package namespace.
6. **Hardware Keychain / Keystore Data**:
   * iOS Keychain access groups and Android Keystore aliases use the bundle ID as their namespace root. Upgrading an existing app with a different bundle ID wipes user credentials.
7. **Dart Module Resolution**:
   * Over 40 files in `lib/` and `test/` use `import 'package:coinvault_ai/...'`. Renaming the Dart package triggers extensive refactoring and breaks git history.
8. **Platform Native Method Channels**:
   * Plugins rely on package namespace matching in `MainActivity.kt` (`package com.coinvault.coinvault_ai`).

### Immutable Policy
Once store setup commences, the following identifiers **MUST REMAIN UNCHANGED**:
* iOS Bundle ID: `com.coinvault.coinvaultAi`
* Android Application ID: `com.coinvault.coinvault_ai`
* Dart Package: `coinvault_ai`
* Product IDs: `com.coinscan.plus.monthly`, `com.coinscan.plus.yearly`, `com.coinscan.pro.monthly`, `com.coinscan.pro.yearly`
* RevenueCat Entitlements: `plus`, `pro`
