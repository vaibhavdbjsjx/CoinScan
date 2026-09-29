# CoinScan Phase 10: Help Center, Support & Feedback Infrastructure

**Date:** 2026-08-29  
**Author:** Principal Product & Quality Architect  
**Document Version:** 1.0.0  
**Status:** **ACTIVE / VERIFIED**

---

## 1. Help Center Architecture & Numismatic Guidelines

CoinScan provides an in-app Help Center (`HelpCenterScreen`) structured into three distinct domains:

1. **Scanning & Identification:**
   - *Why two-sided die capture is required:* Explains master die pairings, mule detection, and variety identification.
   - *How to improve scan quality:* Neutral backgrounds, diffuse lighting, glare mitigation, and perpendicular camera angles.
   - *Confidence score interpretation:* Multi-signal breakdown (visual match + OCR text agreement + Numista catalogue specifications).
2. **Valuation & Pricing Realism:**
   - *Valuation Disclaimers:* Automated numismatic estimates are informational and dependent on exact Sheldon grading and market auction liquidity.
   - *Unavailable Values:* Base-metal modern coins without sufficient auction history display "Value unavailable" rather than fabricated figures.
3. **Subscriptions & Quotas:**
   - Worldwide UTC midnight quota reset schedule.
   - Self-service subscription restoration via Apple ID.

---

## 2. User Feedback & Bug Reporting Subsystem

```
+---------------------------------------------------------------------------------------------------+
|                                 FEEDBACK SUBMISSION ARCHITECTURE                                  |
+---------------------------------------------------------------------------------------------------+

1. User opens Feedback / Report a Problem in Settings or Scan Result Screen.
2. Form Input:
   ├── Category Selection (Identification Issue, Valuation Error, Camera, Subscription, Bug, etc.)
   ├── Summary / Title (min 3 chars, max 150 chars)
   └── Detailed Description (min 5 chars, max 2000 chars)
3. Client attaches non-PII diagnostic metadata:
   ├── App Version (1.0.0) & Build (1)
   ├── Platform (iOS / Android / Web)
   └── Optional scan request ID (if reporting a misidentified coin)
4. Transport over TLS 1.3 to `POST /v1/feedback`.
5. Anti-Spam Rate Limiter: Max 5 submissions per 10-minute window per IP / user.
6. Server logs structured feedback record for numismatic engineering review.
```
