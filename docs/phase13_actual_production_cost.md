# CoinScan Phase 13: Production Infrastructure Cost Model & Scale Projections

**Date:** 2026-08-30  
**Author:** Principal Cloud Infrastructure & Financial Architect  
**Document Version:** 1.0.0  
**Status:** **ACTIVE / VERIFIED**

---

## 1. Unit Variable Cost Baseline

| Component | Provider / Architecture | Pricing Basis | Variable Cost Per Scan |
|---|---|---|---|
| **Vision AI (Obverse + Reverse)** | Google Gemini 2.0 Flash | 2 Images (~1,200 in, ~250 out tokens) | **$0.000220** |
| **Catalogue Lookup & Cross-Check**| Numista Commercial API (24h Cache) | 1 search + 1 type query / 10 scans | **$0.000050** |
| **Precious Metal Spot Valuation** | Metal Price Feed (15m Cache) | In-memory cached spot lookup | **$0.000010** |
| **FX Currency Conversion** | ExchangeRate-API (1h Cache) | In-memory cached FX matrix | **$0.000005** |
| **Cloud Run Dynamic Compute** | Google Cloud Run (2 vCPU, 2GB) | ~1.2s container execution time | **$0.000058** |
| **Total Marginal Cost per Scan** | — | — | **$0.000343** |

---

## 2. Comprehensive Cost Projections Across User Scales

| Active User Scale | Monthly Scans | Cloud Run Sizing (min/max instances) | Vision AI Cost | Cloud Run Cost | Supabase Tier | RevenueCat Fee (1% MTR) | Total Monthly Cloud Cost | Estimated Monthly Revenue (5% conversion) | Gross Margin |
|---|---|---|---|---|---|---|---|---|---|
| **100 Users** | 1,000 | `min=0, max=2` | $0.22 | $1.50 | Free ($0) | $0.00 | **~$1.72** | $30.00 | **94.3%** |
| **1,000 Users** | 10,000 | `min=0, max=5` | $2.20 | $6.00 | Free ($0) | $0.00 | **~$8.20** | $300.00 | **97.3%** |
| **10,000 Users** | 100,000 | `min=1, max=20` (warm instance) | $22.00 | $35.00 | Pro ($25) | $0.00 (<$2.5k MTR) | **~$82.00** | $3,000.00 | **97.3%** |
| **25,000 Users** | 350,000 | `min=1, max=40` | $77.00 | $52.00 | Pro ($25) | $75.00 | **~$229.00** | $7,500.00 | **96.9%** |
| **100,000 Users** | 1,500,000 | `min=2, max=100` | $330.00 | $120.00 | Team ($599) | $300.00 | **~$1,349.00** | $30,000.00 | **95.5%** |

---

## 3. Impact of Cloud Run Cold-Start Strategy & Tier Mix

1. **Cold-Start Sizing Tradeoff:**
   - At early launch (< 5,000 users), `min-instances=0` keeps idle costs at $0.00 while maintaining sub-1.5s cold starts on Python 3.11 slim containers.
   - At production scale (> 10,000 users), keeping `min-instances=1` costs only ~$27.36/month while eliminating 100% of cold-start latency during collector peak hours.
2. **Subscription Mix Resilience:**
   - A single Plus subscriber ($4.99/mo) covers the total variable cost of **14,500 scans**.
   - A single Pro subscriber ($9.99/mo) covers the total variable cost of **29,000 scans**.
   - The business model is extraordinarily resilient against variable computing and AI token costs.
