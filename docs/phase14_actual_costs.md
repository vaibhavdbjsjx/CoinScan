# CoinScan Phase 14: Actual Production Cost Model & Scale Economics

**Date:** 2026-08-30  
**Author:** Principal Cloud Infrastructure & Financial Architect  
**Document Version:** 1.0.0  
**Status:** **ACTIVE / VERIFIED**

---

## 1. Fixed vs. Variable Cost Structure

### A. Fixed Monthly Infrastructure Costs
- **Supabase PostgreSQL & Auth (Pro Plan):** **$25.00 / month** (includes daily backups, RLS, 8GB DB, and Auth).
- **Google Cloud Run (Baseline warm instance: 1 instance @ 2 vCPU, 2GB during peak hours):** **~$27.36 / month** (Optional; $0.00 if `min-instances=0`).
- **Domain & DNS (api.coinscan.app & coinscan.app):** **~$1.00 / month** ($12/year).
- **Total Fixed Base Cost:** **~$53.36 / month**

### B. Variable Unit Costs (Per Scan)
- **Vision AI (Google Gemini 2.0 Flash):** 2 images (~1,200 input tokens, ~250 output tokens) @ $0.10/1M in, $0.40/1M out = **$0.000220**
- **Catalogue Verification (Numista API with 24h caching):** **$0.000050**
- **Precious Metal Spot Valuation (15m in-memory cache):** **$0.000010**
- **FX Rate Conversion (1h in-memory cache):** **$0.000005**
- **Cloud Run Execution Compute (~1.2s dynamic CPU):** **$0.000058**
- **Total Marginal Variable Cost Per Scan:** **$0.000343**

---

## 2. Monthly Financial Projections by User Scale

| Active User Scale | Monthly Scans | Fixed Cloud Cost | Variable AI/Compute Cost | RevenueCat Fee (1% MTR) | Total Monthly Cost | Projected Monthly Revenue (5% Conversion) | Gross Margin (%) |
|---|---|---|---|---|---|---|---|
| **100 Users** | 1,000 | $0.00 *(Free tier)* | $0.34 | $0.00 | **$0.34** | $30.00 | **98.8%** |
| **1,000 Users** | 10,000 | $0.00 *(Free tier)* | $3.43 | $0.00 | **$3.43** | $300.00 | **98.8%** |
| **10,000 Users** | 100,000 | $53.36 *(Pro tier)* | $34.30 | $0.00 *(<$2.5k MTR)* | **$87.66** | $3,000.00 | **97.1%** |
| **25,000 Users** | 350,000 | $53.36 *(Pro tier)* | $120.05 | $75.00 | **$248.41** | $7,500.00 | **96.7%** |
| **100,000 Users** | 1,500,000 | $652.36 *(Team tier)* | $514.50 | $300.00 | **$1,466.86** | $30,000.00 | **95.1%** |

---

## 3. Financial Viability & Abuse Resilience

1. **Massive Coverage Ratio:** A single Plus subscriber ($4.99/mo) covers the total computing and AI cost of **14,500 scans**. A Pro subscriber ($9.99/mo) covers **29,000 scans**.
2. **Quota Cap Security:** Free tier users are hard-capped at 3 scans/day (UTC midnight reset), ensuring unauthenticated or free user usage cannot exceed **$0.03 / user / month**.
