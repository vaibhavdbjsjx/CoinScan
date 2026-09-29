# CoinScan Phase 2 Foundation Audit

Date: 2026-08-26

## Existing Architecture

- Framework: Flutter 3.44.4 stable with Dart 3.12.2.
- App name/package: `coinvault_ai`.
- Entry point: `lib/main.dart`, rendering `CoinVaultApp`.
- Navigation: `go_router` for onboarding/login/main app, with native `MaterialPageRoute` pushes for scanner and detail screens.
- State management: mostly local `StatefulWidget` state. `flutter_bloc` is installed but not used in the inspected production path.
- Platforms present: iOS, Android, web, macOS, Linux, and Windows folders exist.
- iOS deployment target: 13.0.
- App shell: `MainNavigationWrapper` with Home, Vault, Market, Profile tabs and a central scanner action.
- Theming: custom theme, color, typography, token, and premium widget layers.

## What Already Works

- Onboarding, login bypass, home, collection vault, marketplace, profile, and detail screens render in widget tests.
- The scanner has a polished multi-step UI for front, reverse, and optional edge capture.
- The UI has meaningful safe-area handling in major shell/scanner surfaces.
- The existing mock data powers collection, market, profile, education, and chart demos.
- Web production build was previously verified.

## What Is Mocked Or Demo

- Coin recognition is not real.
- The scanner previously routed to `MockApi.collectibles[0]` after a timed animation.
- `MockApi.simulateScan` returns sample collectibles after a delay.
- Coin records, confidence scores, authenticity reasons, grade explanations, valuation ranges, price histories, portfolio items, marketplace listings, lessons, achievements, collector profile, and series goals are demo data.
- There is no real backend/API client.
- There is no real camera package, photo-library package, OCR, ML model, recognition provider, database, auth provider, or subscription provider.
- The chart price history is generated locally with pseudo-random math.

## Current Recognition Pipeline

Actual current state after Phase 2 foundation changes:

Camera/gallery image -> not implemented yet
Preprocessing -> not implemented yet
Recognition service interface -> established
Recognition provider -> unavailable provider only
Coin knowledge database -> not implemented yet
Result -> truthful unavailable state

The production scan path no longer returns a fake coin identity.

## iOS Verification

- Xcode found: 26.6.
- iOS project exists.
- iOS deployment target: 13.0.
- No available simulator devices were returned by `xcrun simctl list devices available`.
- Physical iPhone verification: not verified.
- iOS camera permission prompt: not verified.
- Camera usage description: missing before real camera integration.
- Photo library usage description: missing before gallery integration.

## Security And Git

- Git history exists with one initial commit.
- Worktree is dirty from existing project work and this phase.
- `.gitignore` excludes Flutter build output, Dart tooling, coverage, logs, and common IDE files.
- No obvious embedded API keys were found in the inspected code.
- No GitHub remote/push verification was performed in this phase.
- Private AI/API keys must never be placed in Flutter. The mobile app should call a CoinScan backend.

## Production Foundation Added

- `RecognitionService` and structured recognition candidates/evidence.
- `ValuationService` with separate face, metal, collector, and market valuation concepts.
- `CurrencyRateService` with timestamped provider rates.
- `SubscriptionService` with UI-independent entitlement state.

## Remaining Blockers

- Real camera capture is not implemented.
- Gallery import is not implemented.
- iOS simulator/device behavior is not verified because no available simulator/device was detected.
- Recognition backend and provider are not connected.
- Coin knowledge database does not exist.
- Valuation data providers and comparables are not connected.
- App Store subscription products and StoreKit entitlements are not configured.
- Privacy policy and image retention behavior are not implemented.

## Recommended Next Single Step

Implement real iOS camera and gallery capture behind the existing scanner UI, including Info.plist permission strings, review/retake states, and tests that prove captured images enter the shared `RecognitionService` pipeline.
