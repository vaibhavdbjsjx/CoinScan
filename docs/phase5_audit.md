# CoinScan Phase 5: Repository & Architecture Audit

**Date:** 2026-08-26  
**Auditor:** Senior Backend & Platform Engineer  
**Target:** Production CoinScan Recognition System

---

## 1. Executive Summary

A comprehensive line-by-line inspection of the Flutter application, dependencies, domain models, navigation, and configuration was performed before implementing Phase 5.

### Key Findings:
1. **Flutter Mobile UI & Camera:** The camera preview, hardware controls (focus/flash), gallery import, and multi-step capture workflow (`front` $\to$ `reverse` $\to$ `edge`) in [lib/features/scan/scan_screen.dart](file:///Users/vaibhavsg/Documents/coinscan/lib/features/scan/scan_screen.dart) are fully functional with zero memory leaks and proper lifecycle disposal.
2. **Recognition Domain Models:** [lib/core/recognition/recognition_models.dart](file:///Users/vaibhavsg/Documents/coinscan/lib/core/recognition/recognition_models.dart) contains normalized, production-ready abstractions (`ImageQualityReport`, `CoinIdentity`, `RecognitionConfidence`, `RecognitionEvidence`, `RecognitionCandidate`, `RecognitionResult`) with complete JSON serialization.
3. **Valuation & Currency Layers:** [lib/core/valuation/valuation_models.dart](file:///Users/vaibhavsg/Documents/coinscan/lib/core/valuation/valuation_models.dart) and [lib/core/currency/currency_models.dart](file:///Users/vaibhavsg/Documents/coinscan/lib/core/currency/currency_models.dart) properly segregate economic value into 4 dimensions (Face, Metal Melt, Catalogue Guide, Realized Comparables) with TTL-cached FX conversions.
4. **Current Recognition Boundary:** `ScanScreen` utilizes `UnavailableRecognitionService`, which returns `RecognitionResult.unavailable` directly. The UI currently displays `_UnavailableRecognitionState`.
5. **Zero Mock Leakage in Scan Pipeline:** `MockApi` exists exclusively in secondary presentation tabs (Marketplace, Profile, Home, Collection). No fake coins or simulated scan routines exist in the scanner.
6. **Backend Infrastructure:** No backend server existed in the repository.

---

## 2. Component-by-Component Status Matrix

| Component | Path | Current State | Functionality Level | Action Required in Phase 5 |
| :--- | :--- | :--- | :--- | :--- |
| **Scanner UI** | `lib/features/scan/scan_screen.dart` | Working | Real camera capture & review | Connect to `HttpRecognitionService` and build rich multi-state result view |
| **Recognition Domain** | `lib/core/recognition/recognition_models.dart` | Working | Complete domain models & serialization | Preserve and maintain compatibility |
| **Recognition Client** | `lib/core/recognition/http_recognition_service.dart` | Missing | N/A | **Implement** robust HTTP client with timeout, error handling, base URL config |
| **Valuation Domain** | `lib/core/valuation/valuation_models.dart` | Working | 4-tier valuation structure | Preserve |
| **Currency Domain** | `lib/core/currency/currency_models.dart` | Working | In-memory cached FX service | Preserve |
| **Backend Service** | `backend/` | Missing | N/A | **Build** Python FastAPI backend with vision, OCR, Numista client, ranking & valuation |
| **Environment Config** | `.env.example`, `.gitignore` | Baseline | Template in root | Update with backend-specific variables and protect `.env` in `.gitignore` |
| **Test Suite** | `test/widget_test.dart`, `test/recognition_architecture_test.dart` | Passing | 26/26 tests passing | Add Flutter HTTP recognition tests & backend pytest suite |

---

## 3. What Must Be Preserved vs Replaced

### Preserved:
- All Flutter camera lifecycle, permission handling, and viewfinders in `ScanScreen`.
- The `CapturedCoinImage`, `CoinScanInput`, and `RecognitionService` interface abstractions.
- The 4-tier valuation model (`faceValue`, `metalValue`, `collectorValue`, `marketEstimate`).
- The multi-signal confidence structure and evidence typing.
- All existing 26 unit and widget tests.

### Replaced / Implemented:
- Replace `UnavailableRecognitionService` as the default in `ScanScreen` with `HttpRecognitionService` (while allowing injection of mock services for headless tests).
- Replace the simple `_UnavailableRecognitionState` with a full-featured `_RecognitionResultView` supporting Identified, Candidate, Low Confidence, Unknown, and Error states.
- Implement the containerized Python FastAPI backend service under `backend/`.
