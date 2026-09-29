# CoinScan Phase 8: Worldwide Pricing Strategy & Unit Economics

**Date:** 2026-08-27  
**Author:** Senior Staff Platform & Monetization Architect  
**Document Version:** 1.0.0  
**Status:** **ACTIVE / VERIFIED**

---

## 1. Executive Strategy & Market Context

CoinScan is designed as a premium, worldwide numismatic tool for collectors, dealers, and casual coin discoverers. Competing coin identification apps (e.g. CoinSnap, Coinoscope) typically charge between $29.99/yr and $39.99/yr, but suffer from low trust due to hallucinated valuations and inaccurate identification of rare varieties.

CoinScan differentiates itself with:
1. **Multi-sided physical verification** (Obverse + Reverse + optional Edge die alignment).
2. **Transparent confidence breakdowns** (Visual similarity + OCR inscription agreement + Numista catalogue verification).
3. **Four-layer valuation modeling** (Face value, Fine metal melt value, Numismatic collector estimates, Realized auction records).

---

## 2. Recommended Production Product Line & Pricing

Apple App Store will automatically localize these baseline USD tiers across worldwide storefronts (EUR, GBP, JPY, CAD, AUD, etc.) using Apple's standard equalization tier matrix.

```
+---------------------------------------------------------------------------------------------------------+
|                                    COINSCAN PRODUCT TIERS & PRICING                                     |
+-------------------+-------------------+-------------------+-----------------------+---------------------+
| Tier              | Monthly Price     | Annual Price      | Scan Allowance        | Core Features       |
+-------------------+-------------------+-------------------+-----------------------+---------------------+
| 1. Limited (Free) | $0.00             | $0.00             | 3 scans / day         | Standard AI ID      |
|                   |                   |                   | (Reset UTC 00:00)     | Basic specs         |
+-------------------+-------------------+-------------------+-----------------------+---------------------+
| 2. Plus           | $4.99 / mo        | $39.99 / yr       | 30 scans / day        | Multi-sided ID      |
|                   |                   | ($3.33/mo equiv.) | (~900 scans / mo)     | High-res OCR        |
|                   |                   | (33% discount)    |                       | Local history sync  |
+-------------------+-------------------+-------------------+-----------------------+---------------------+
| 3. Pro            | $9.99 / mo        | $79.99 / yr       | Fair-Use High Cap:    | Full Multi-sided ID |
|                   |                   | ($6.66/mo equiv.) | 100 scans / day       | 4-layer valuation   |
|                   |                   | (33% discount)    | (~3,000 scans / mo)   | Live Bullion/FX     |
|                   |                   |                   | (No hard lock, alert) | Cloud backup        |
+-------------------+-------------------+-------------------+-----------------------+---------------------+
```

---

## 3. Unit Economics & Cost Breakdown Analysis

### 3.1 Per-Scan Variable Infrastructure Cost

Each scan invocation on CoinScan triggers:
1. **Google Cloud Run compute:** Image preprocessing, Laplacian sharpness check, normalization: **~$0.0002**
2. **Vision AI Inference (Google Gemini 2.0 Flash):** 2 images @ ~258 tokens each (~1,500 total tokens in/out): **~$0.0006**
3. **Numista API v3 Lookup:** Cached numismatic catalogue query: **~$0.0001**
4. **Metals & FX Service (Pro only):** In-memory cached spot rate lookup: **~$0.0001**
5. **Total Variable Cost per Scan:** **~$0.0010 (1/10th of one cent)**

### 3.2 Tier Gross Margin Analysis

#### Plus Tier ($39.99/year or ~$3.33/month average)
- Average expected subscriber usage: **60 scans / month** (~2 scans/day)
- Heavy active collector usage (95th percentile): **300 scans / month** (~10 scans/day)
- Monthly Infrastructure Cost (Average user): $0.0010 × 60 = **$0.06 / month**
- Monthly Infrastructure Cost (Heavy user): $0.0010 × 300 = **$0.30 / month**
- Apple App Store Commission (15% Small Business Program): **$0.50 / month**
- RevenueCat Infrastructure Cost (1% over $2.5k MTR): **$0.03 / month**
- **Net Profit per Plus Subscriber (Average):** $3.33 - $0.06 - $0.50 - $0.03 = **$2.74 / month (~82% Net Margin)**

#### Pro Tier ($79.99/year or ~$6.66/month average)
- Average expected subscriber usage: **150 scans / month** (~5 scans/day)
- Heavy dealer / active power user: **800 scans / month** (~26 scans/day)
- Monthly Infrastructure Cost (Average user): $0.0010 × 150 = **$0.15 / month**
- Monthly Infrastructure Cost (Heavy dealer): $0.0010 × 800 = **$0.80 / month**
- Apple App Store Commission (15%): **$1.00 / month**
- RevenueCat Infrastructure: **$0.07 / month**
- **Net Profit per Pro Subscriber (Average):** $6.66 - $0.15 - $1.00 - $0.07 = **$5.44 / month (~81.6% Net Margin)**

---

## 4. Fair-Use & Anti-Abuse Strategy

1. **Why "Unlimited" Must Be Fair-Use Capped on Backend:**
   - Truly unbounded scans invite automated scraping, bot attacks, and account sharing across multiple dealers.
   - Pro tier provides an extremely generous **100 scans per day** (~3,000 per month), which satisfies 99.9% of human collectors and professional dealers.
   - If a user exceeds 100 scans in a 24-hour UTC window, the backend enforces a cooling period with a transparent message to contact sales for the high-volume Developer API tier.
2. **Daily Quota Reset Boundary:**
   - Quotas reset deterministically at **00:00:00 UTC** worldwide.
   - Prevents timezone manipulation attacks on client devices.
3. **Sliding-Window Rate Limiting:**
   - Free/Limited tier: Max **5 scans / minute** (prevents burst spam).
   - Plus tier: Max **15 scans / minute**.
   - Pro tier: Max **30 scans / minute**.

---

## 5. RevenueCat Infrastructure Integration Specification

### 5.1 Entitlements & Product Mapping in RevenueCat
- **Entitlement ID:** `coinscan_plus`
  - Products attached: `com.coinscan.plus.monthly`, `com.coinscan.plus.yearly`
- **Entitlement ID:** `coinscan_pro`
  - Products attached: `com.coinscan.pro.monthly`, `com.coinscan.pro.yearly`
- **Offering ID:** `default`
  - Packages: `$rc_monthly`, `$rc_annual`

### 5.2 Server-to-Server Webhook Flow
1. User completes StoreKit purchase on iOS device.
2. RevenueCat verifies Apple App Store cryptographic receipt / StoreKit 2 JWS transaction.
3. RevenueCat updates client SDK entitlement immediately.
4. RevenueCat fires authenticated HTTP POST webhook to `https://api.coinscan.app/v1/webhooks/revenuecat`.
5. CoinScan FastAPI backend verifies webhook bearer token, records event in `subscription_events`, and updates `subscriptions` / `entitlements` tables in PostgreSQL / Supabase idempotently.
6. When client scans coins, backend validates server-side entitlement directly.
